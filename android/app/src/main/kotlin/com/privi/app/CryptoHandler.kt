package com.privi.app

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import android.util.Log

/**
 * Hardware-accelerated AES-256-GCM file encryption / decryption.
 *
 * Uses Android's javax.crypto.Cipher which delegates to hardware-accelerated
 * implementations (AES-NI / ARMv8 crypto extensions) through the platform's
 * security provider.
 *
 * File format: [nonce:12][ciphertext:N][auth_tag:16]
 */
class CryptoHandler {
    companion object {
        private const val TAG = "PriviCrypto"
        private const val GCM_TAG_LENGTH = 128 // bits
        private const val GCM_NONCE_LENGTH = 12 // bytes
        private const val CHUNK_SIZE = 1024 * 1024 // 1 MiB
        private const val AES_KEY_SIZE = 32 // 256 bits
    }

    /** Encrypt file in-place: replaces [filePath] content with encrypted data. */
    fun encryptFile(
        filePath: String,
        dek: ByteArray,
        nonce: ByteArray,
    ): Map<String, Any?> {
        val inputFile = File(filePath)
        val bakFile = File(filePath + ".enc_bak")
        if (!inputFile.exists()) {
            // Self-heal a crash between "original → .enc_bak" and
            // "temp → original": the media is still sitting in the backup slot.
            if (bakFile.exists() && bakFile.renameTo(inputFile)) {
                Log.w(TAG, "Recovered interrupted encryption: $filePath")
            } else {
                return mapOf("ok" to false, "error" to "File not found: $filePath")
            }
        }
        val originalLength = inputFile.length()
        val tmpFile = File(filePath + ".enc_tmp")
        if (tmpFile.exists()) tmpFile.delete() // stale half-written ciphertext

        try {
            val key = SecretKeySpec(dek, "AES")
            val spec = GCMParameterSpec(GCM_TAG_LENGTH, nonce)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key, spec)

            FileInputStream(inputFile).use { input ->
                FileOutputStream(tmpFile).use { output ->
                    // Write nonce header first
                    output.write(nonce)

                    val buffer = ByteArray(CHUNK_SIZE)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } > 0) {
                        val encrypted = cipher.update(buffer, 0, bytesRead)
                        if (encrypted != null) {
                            output.write(encrypted)
                        }
                    }
                    // Final block + 16-byte auth tag
                    val finalBlock = cipher.doFinal()
                    output.write(finalBlock)
                }
            }

            // Atomic replace: backup original → rename temp → delete backup.
            // Never delete-then-rename: a crash between the two steps permanently
            // loses the file (PIT-034).  On the same filesystem rename is atomic.
            if (!inputFile.renameTo(bakFile)) {
                tmpFile.delete()
                return mapOf("ok" to false, "error" to "Failed to back up original file")
            }
            if (!tmpFile.renameTo(inputFile)) {
                tmpFile.delete()
                if (!bakFile.renameTo(inputFile)) {
                    // Keep the backup on disk: deleting it here would destroy
                    // the only remaining copy of the user's media.
                    Log.e(TAG, "Encrypt rename failed, original kept at ${bakFile.path}")
                    return mapOf(
                        "ok" to false,
                        "error" to "Failed to replace original file; it was preserved as ${bakFile.name}",
                    )
                }
                return mapOf("ok" to false, "error" to "Failed to rename temp file (restored backup)")
            }
            bakFile.delete()

            val encryptedLength = inputFile.length()
            Log.i(TAG, "Encrypted: $filePath ($originalLength -> $encryptedLength bytes)")
            return mapOf(
                "ok" to true,
                "originalSize" to originalLength,
                "encryptedSize" to encryptedLength,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Encrypt failed: $filePath", e)
            tmpFile.delete()
            return mapOf("ok" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    /** Decrypt file and write plaintext to [destPath]. */
    fun decryptFile(
        filePath: String,
        destPath: String,
        dek: ByteArray,
    ): Map<String, Any?> {
        val inputFile = File(filePath)
        if (!inputFile.exists()) {
            return mapOf("ok" to false, "error" to "File not found: $filePath")
        }
        val fileLength = inputFile.length()
        // 12-byte nonce + 16-byte tag is the exact minimum: a 0-byte plaintext
        // encrypts to exactly 28 bytes, so rejecting 28 made empty media
        // undecryptable.
        val minLength = GCM_NONCE_LENGTH + GCM_TAG_LENGTH / 8
        if (fileLength < minLength) {
            return mapOf("ok" to false, "error" to "File too small to be encrypted: $fileLength bytes")
        }

        val outputFile = File(destPath)
        outputFile.parentFile?.mkdirs()

        try {
            // Read nonce from file header
            val nonce = ByteArray(GCM_NONCE_LENGTH)
            RandomAccessFile(inputFile, "r").use { raf ->
                raf.readFully(nonce)
            }

            // Read auth tag from end of file
            val tag = ByteArray(GCM_TAG_LENGTH / 8)
            RandomAccessFile(inputFile, "r").use { raf ->
                raf.seek(fileLength - tag.size)
                raf.readFully(tag)
            }

            val key = SecretKeySpec(dek, "AES")
            val spec = GCMParameterSpec(GCM_TAG_LENGTH, nonce)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, spec)

            // Ciphertext range: after nonce, before tag
            val ciphertextStart = GCM_NONCE_LENGTH.toLong()
            val ciphertextLength = fileLength - GCM_NONCE_LENGTH - tag.size

            FileInputStream(inputFile).use { input ->
                // Skip the nonce.  InputStream.skip may advance fewer bytes than
                // asked (it is a hint, not a guarantee) — a short skip would
                // feed nonce bytes into GCM and fail the auth tag check.
                var skipped = 0L
                while (skipped < ciphertextStart) {
                    val step = input.skip(ciphertextStart - skipped)
                    if (step <= 0) break
                    skipped += step
                }
                FileOutputStream(outputFile).use { output ->
                    val buffer = ByteArray(CHUNK_SIZE)
                    var remaining = ciphertextLength
                    while (remaining > 0) {
                        val toRead = minOf(remaining, buffer.size.toLong()).toInt()
                        val bytesRead = input.read(buffer, 0, toRead)
                        if (bytesRead <= 0) break
                        val decrypted = cipher.update(buffer, 0, bytesRead)
                        if (decrypted != null) {
                            output.write(decrypted)
                        }
                        remaining -= bytesRead
                    }
                    // Final block with auth tag verification
                    val finalBlock = cipher.doFinal(tag)
                    if (finalBlock != null && finalBlock.isNotEmpty()) {
                        output.write(finalBlock)
                    }
                }
            }

            Log.i(TAG, "Decrypted: $filePath -> $destPath (${outputFile.length()} bytes)")
            return mapOf(
                "ok" to true,
                "plaintextSize" to outputFile.length(),
            )
        } catch (e: javax.crypto.AEADBadTagException) {
            Log.e(TAG, "Decrypt auth failed: $filePath (tag mismatch)", e)
            outputFile.delete()
            return mapOf("ok" to false, "error" to "Authentication failed: file may be corrupted or tampered with")
        } catch (e: Exception) {
            Log.e(TAG, "Decrypt failed: $filePath", e)
            outputFile.delete()
            return mapOf("ok" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    /** Decrypt to a ByteArray (for small files or in-memory use). */
    fun decryptFileToBytes(
        filePath: String,
        dek: ByteArray,
    ): Map<String, Any?> {
        val inputFile = File(filePath)
        if (!inputFile.exists()) {
            return mapOf("ok" to false, "error" to "File not found: $filePath")
        }
        val fileLength = inputFile.length()
        // Same 28-byte floor as decryptFile: nonce + tag only.
        val minLength = GCM_NONCE_LENGTH + GCM_TAG_LENGTH / 8
        if (fileLength < minLength) {
            return mapOf("ok" to false, "error" to "File too small to be encrypted: $fileLength bytes")
        }
        // Safety limit: don't load > 512 MiB into memory
        if (fileLength > 512L * 1024 * 1024) {
            return mapOf("ok" to false, "error" to "File too large for in-memory decryption, use file output instead")
        }

        try {
            val fileBytes = inputFile.readBytes()
            val nonce = fileBytes.copyOfRange(0, GCM_NONCE_LENGTH)
            val ciphertext = fileBytes.copyOfRange(GCM_NONCE_LENGTH, fileBytes.size)
            // Last 16 bytes = auth tag, rest = ciphertext
            if (ciphertext.size < GCM_TAG_LENGTH / 8) {
                return mapOf("ok" to false, "error" to "Invalid encrypted file format")
            }
            val tag = ciphertext.copyOfRange(ciphertext.size - GCM_TAG_LENGTH / 8, ciphertext.size)
            val actualCiphertext = ciphertext.copyOfRange(0, ciphertext.size - GCM_TAG_LENGTH / 8)

            val key = SecretKeySpec(dek, "AES")
            val spec = GCMParameterSpec(GCM_TAG_LENGTH, nonce)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, key, spec)

            val plaintext = cipher.doFinal(actualCiphertext + tag)
            return mapOf("ok" to true, "bytes" to plaintext, "plaintextSize" to plaintext.size)
        } catch (e: javax.crypto.AEADBadTagException) {
            return mapOf("ok" to false, "error" to "Authentication failed: file may be corrupted or tampered with")
        } catch (e: Exception) {
            Log.e(TAG, "DecryptToBytes failed: $filePath", e)
            return mapOf("ok" to false, "error" to (e.message ?: "Unknown error"))
        }
    }
}