package com.privi.app

import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
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

        /**
         * Container v2 — chunked AES-GCM, constant memory.
         *
         * Layout:
         * ```
         * [magic 'PRV2' 4][baseNonce 8][plaintextSize 8][chunkSize 4][chunk 0..n-1]
         * chunk = ciphertext(min(chunkSize, remaining)) + authTag(16)
         * chunk nonce = baseNonce || int32be(index)
         * ```
         * Why: a **single** GCM stream makes Conscrypt allocate roughly twice the
         * file size inside `Cipher.doFinal` (it buffers the whole payload before
         * the tag can be verified).  With a 71 MB video that is ~140 MB in one
         * allocation, which killed the app with `OutOfMemoryError`
         * (`密册_crash_2026-10-13.txt`, ISSUE-032).  Per-chunk tags keep peak
         * memory at ~2 MiB regardless of file size.
         *
         * v1 (legacy) files are `[nonce 12][ciphertext][tag 16]` and are still
         * decryptable.
         */
        private val MAGIC_V2 = byteArrayOf(0x50, 0x52, 0x56, 0x32) // 'PRV2'
        private const val V2_HEADER_SIZE = 4 + 8 + 8 + 4 // 24
        private const val V2_CHUNK_SIZE = 1024 * 1024 // 1 MiB

        /**
         * Per-path locks: concurrent encryptions of the same file used to share
         * a single `.enc_tmp` and destroy each other's output, leaving 0-byte
         * media behind (ISSUE-030).
         */
        private val pathLocks = ConcurrentHashMap<String, Any>()
    }

    /**
     * Encrypt file in-place: replaces [filePath] content with encrypted data.
     *
     * Calls for the **same path** are serialized and the temp file name is
     * unique: a fixed `.enc_tmp` was shared by parallel loops, which deleted
     * each other's output and left 0-byte media behind (ISSUE-030).
     */
    fun encryptFile(
        filePath: String,
        dek: ByteArray,
        nonce: ByteArray,
    ): Map<String, Any?> = synchronized(lockFor(filePath)) {
        val inputFile = File(filePath)
        val bakFile = File(filePath + ".enc_bak")
        deleteStaleTemps(inputFile)
        if (!inputFile.exists()) {
            // Self-heal a crash between "original → .enc_bak" and
            // "temp → original": the media is still sitting in the backup slot.
            if (bakFile.exists() && bakFile.renameTo(inputFile)) {
                Log.w(TAG, "Recovered interrupted encryption: $filePath")
            } else {
                return@synchronized mapOf("ok" to false, "error" to "File not found: $filePath")
            }
        }
        val originalLength = inputFile.length()
        val tmpFile = File("$filePath.enc_tmp-${UUID.randomUUID()}")

        try {
            val key = SecretKeySpec(dek, "AES")
            // v2 needs an 8-byte base nonce: the caller still hands us the
            // 12-byte v1 nonce, so take its first 8 bytes and let every chunk
            // append its own 4-byte index.
            val baseNonce = ByteArray(8)
            System.arraycopy(nonce, 0, baseNonce, 0, minOf(baseNonce.size, nonce.size))

            FileInputStream(inputFile).use { input ->
                FileOutputStream(tmpFile).use { output ->
                    output.write(MAGIC_V2)
                    output.write(baseNonce)
                    output.write(longToBytes(originalLength))
                    output.write(intToBytes(V2_CHUNK_SIZE))

                    val buffer = ByteArray(V2_CHUNK_SIZE)
                    var index = 0
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break
                        // Fresh cipher per chunk: doFinal() returns at most
                        // chunkSize + 16 bytes, so peak memory stays ~2 MiB no
                        // matter how large the media is (ISSUE-032).
                        val cipher = aesGcmCipher(
                            Cipher.ENCRYPT_MODE,
                            key,
                            chunkNonce(baseNonce, index),
                        )
                        output.write(cipher.doFinal(buffer, 0, read))
                        index++
                    }
                }
            }

            // Atomic replace: backup original → rename temp → delete backup.
            // Never delete-then-rename: a crash between the two steps permanently
            // loses the file (PIT-034).  On the same filesystem rename is atomic.
            if (!inputFile.renameTo(bakFile)) {
                tmpFile.delete()
                return@synchronized mapOf("ok" to false, "error" to "Failed to back up original file")
            }
            if (!tmpFile.renameTo(inputFile)) {
                tmpFile.delete()
                if (!bakFile.renameTo(inputFile)) {
                    // Keep the backup on disk: deleting it here would destroy
                    // the only remaining copy of the user's media.
                    Log.e(TAG, "Encrypt rename failed, original kept at ${bakFile.path}")
                    return@synchronized mapOf(
                        "ok" to false,
                        "error" to "Failed to replace original file; it was preserved as ${bakFile.name}",
                    )
                }
                return@synchronized mapOf("ok" to false, "error" to "Failed to rename temp file (restored backup)")
            }

            // Lower bound: header + one tag per chunk.  Anything shorter means
            // the swap went wrong (for example two writers sharing a temp file)
            // — never keep such a file (ISSUE-030).
            val encryptedLength = inputFile.length()
            val minimumLength = V2_HEADER_SIZE.toLong() +
                (originalLength / V2_CHUNK_SIZE + 1) * (GCM_TAG_LENGTH / 8).toLong()
            if (encryptedLength < minimumLength) {
                Log.e(
                    TAG,
                    "Encrypt produced $encryptedLength bytes for $originalLength input; restoring original",
                )
                inputFile.delete()
                if (bakFile.exists() && !bakFile.renameTo(inputFile)) {
                    Log.e(TAG, "Original could not be restored; kept at ${bakFile.path}")
                    return@synchronized mapOf(
                        "ok" to false,
                        "error" to "Encryption produced a truncated file; original kept as ${bakFile.name}",
                    )
                }
                return@synchronized mapOf(
                    "ok" to false,
                    "error" to "Encryption produced a truncated file; original restored",
                )
            }
            bakFile.delete()

            Log.i(TAG, "Encrypted(v2): $filePath ($originalLength -> $encryptedLength bytes)")
            return@synchronized mapOf(
                "ok" to true,
                "originalSize" to originalLength,
                "encryptedSize" to encryptedLength,
            )
        } catch (e: OutOfMemoryError) {
            // Chunked encryption should never get here, but never let the
            // process die: restore the original and report instead.
            Log.e(TAG, "Encrypt ran out of memory: $filePath", e)
            tmpFile.delete()
            restoreBackupIfNeeded(inputFile, bakFile)
            return@synchronized mapOf(
                "ok" to false,
                "error" to "Out of memory while encrypting: file too large",
            )
        } catch (e: Exception) {
            Log.e(TAG, "Encrypt failed: $filePath", e)
            tmpFile.delete()
            restoreBackupIfNeeded(inputFile, bakFile)
            return@synchronized mapOf("ok" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    /** Serializes encryption of the same path inside this process. */
    private fun lockFor(path: String): Any = pathLocks.computeIfAbsent(path) { Any() }

    /** Removes temp files left behind by an older build or a crash. */
    private fun deleteStaleTemps(inputFile: File) {
        val parent = inputFile.parentFile ?: return
        val prefix = inputFile.name + ".enc_tmp"
        parent.listFiles { file -> file.isFile && file.name.startsWith(prefix) }?.forEach {
            if (!it.delete()) Log.w(TAG, "Could not delete stale temp ${it.path}")
        }
    }

    /** Puts the pre-encryption original back when the new file is missing/empty. */
    private fun restoreBackupIfNeeded(inputFile: File, bakFile: File) {
        if (inputFile.exists() && inputFile.length() > 0) return
        if (!bakFile.exists()) return
        if (inputFile.exists()) inputFile.delete()
        if (bakFile.renameTo(inputFile)) {
            Log.w(TAG, "Restored original from backup: ${inputFile.path}")
        } else {
            Log.e(TAG, "Could not restore original; it stays at ${bakFile.path}")
        }
    }

    private fun aesGcmCipher(mode: Int, key: SecretKeySpec, nonce: ByteArray): Cipher {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(mode, key, GCMParameterSpec(GCM_TAG_LENGTH, nonce))
        return cipher
    }

    /** Chunk nonce = baseNonce(8) || index(4, big-endian) → always 12 bytes. */
    private fun chunkNonce(baseNonce: ByteArray, index: Int): ByteArray {
        val nonce = ByteArray(GCM_NONCE_LENGTH)
        System.arraycopy(baseNonce, 0, nonce, 0, minOf(baseNonce.size, 8))
        nonce[8] = ((index ushr 24) and 0xFF).toByte()
        nonce[9] = ((index ushr 16) and 0xFF).toByte()
        nonce[10] = ((index ushr 8) and 0xFF).toByte()
        nonce[11] = (index and 0xFF).toByte()
        return nonce
    }

    private fun intToBytes(value: Int): ByteArray = byteArrayOf(
        ((value ushr 24) and 0xFF).toByte(),
        ((value ushr 16) and 0xFF).toByte(),
        ((value ushr 8) and 0xFF).toByte(),
        (value and 0xFF).toByte(),
    )

    private fun longToBytes(value: Long): ByteArray {
        val out = ByteArray(8)
        for (i in 0 until 8) {
            out[i] = ((value ushr (56 - 8 * i)) and 0xFF).toByte()
        }
        return out
    }

    private fun bytesToInt(bytes: ByteArray, offset: Int): Int =
        ((bytes[offset].toInt() and 0xFF) shl 24) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
            ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
            (bytes[offset + 3].toInt() and 0xFF)

    private fun bytesToLong(bytes: ByteArray, offset: Int): Long {
        var value = 0L
        for (i in 0 until 8) {
            value = (value shl 8) or (bytes[offset + i].toLong() and 0xFF)
        }
        return value
    }

    /** Reads exactly [buf].size bytes — InputStream.read is partial by contract. */
    private fun readFully(input: java.io.InputStream, buf: ByteArray): Boolean {
        var read = 0
        while (read < buf.size) {
            val step = input.read(buf, read, buf.size - read)
            if (step <= 0) return false
            read += step
        }
        return true
    }

    private fun skipFully(input: java.io.InputStream, count: Long): Boolean {
        var skipped = 0L
        while (skipped < count) {
            val step = input.skip(count - skipped)
            if (step <= 0) return false
            skipped += step
        }
        return true
    }

    private fun isV2(inputFile: File): Boolean {
        if (inputFile.length() < V2_HEADER_SIZE) return false
        return try {
            RandomAccessFile(inputFile, "r").use { raf ->
                val magic = ByteArray(MAGIC_V2.size)
                raf.readFully(magic)
                magic.contentEquals(MAGIC_V2)
            }
        } catch (e: Exception) {
            false
        }
    }

    private data class V2Header(
        val baseNonce: ByteArray,
        val plaintextSize: Long,
        val chunkSize: Int,
    )

    private fun readV2Header(inputFile: File): V2Header? = try {
        RandomAccessFile(inputFile, "r").use { raf ->
            val header = ByteArray(V2_HEADER_SIZE)
            raf.readFully(header)
            if (!header.copyOfRange(0, MAGIC_V2.size).contentEquals(MAGIC_V2)) {
                null
            } else {
                val baseNonce = header.copyOfRange(4, 12)
                val plaintextSize = bytesToLong(header, 12)
                val chunkSize = bytesToInt(header, 20)
                if (plaintextSize < 0 || chunkSize <= 0 || chunkSize > 64 * 1024 * 1024) {
                    Log.e(TAG, "Invalid v2 header: size=$plaintextSize chunk=$chunkSize")
                    null
                } else {
                    V2Header(baseNonce, plaintextSize, chunkSize)
                }
            }
        }
    } catch (e: Exception) {
        Log.e(TAG, "Failed to read v2 header: ${inputFile.path}", e)
        null
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
        // v2 container (chunked GCM): constant memory, safe for large media.
        if (isV2(inputFile)) {
            val v2Output = File(destPath)
            v2Output.parentFile?.mkdirs()
            return try {
                decryptV2File(inputFile, v2Output, dek)
            } catch (e: OutOfMemoryError) {
                Log.e(TAG, "Decrypt ran out of memory: $filePath", e)
                v2Output.delete()
                mapOf("ok" to false, "error" to "Out of memory while decrypting: file too large")
            } catch (e: javax.crypto.AEADBadTagException) {
                Log.e(TAG, "Decrypt auth failed: $filePath (tag mismatch)", e)
                v2Output.delete()
                mapOf("ok" to false, "error" to "Authentication failed: file may be corrupted or tampered with")
            } catch (e: Exception) {
                Log.e(TAG, "Decrypt failed: $filePath", e)
                v2Output.delete()
                mapOf("ok" to false, "error" to (e.message ?: "Unknown error"))
            }
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

            Log.i(TAG, "Decrypted(v1): $filePath -> $destPath (${outputFile.length()} bytes)")
            return mapOf(
                "ok" to true,
                "plaintextSize" to outputFile.length(),
            )
        } catch (e: OutOfMemoryError) {
            // Legacy single-stream files can still exhaust the heap when huge;
            // report instead of letting the process die (ISSUE-032).
            Log.e(TAG, "Decrypt ran out of memory: $filePath", e)
            outputFile.delete()
            return mapOf("ok" to false, "error" to "Out of memory while decrypting: file too large")
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

    /** v2: chunked GCM — peak memory stays around one 1 MiB chunk. */
    private fun decryptV2File(
        inputFile: File,
        outputFile: File,
        dek: ByteArray,
    ): Map<String, Any?> {
        val header = readV2Header(inputFile)
            ?: return mapOf("ok" to false, "error" to "Invalid encrypted file format")
        val key = SecretKeySpec(dek, "AES")
        FileInputStream(inputFile).use { input ->
            if (!skipFully(input, V2_HEADER_SIZE.toLong())) {
                return mapOf("ok" to false, "error" to "Invalid encrypted file format")
            }
            FileOutputStream(outputFile).use { output ->
                var remaining = header.plaintextSize
                var index = 0
                while (remaining > 0) {
                    val thisLength = minOf(remaining, header.chunkSize.toLong()).toInt()
                    val payload = ByteArray(thisLength + GCM_TAG_LENGTH / 8)
                    if (!readFully(input, payload)) {
                        return mapOf("ok" to false, "error" to "Encrypted file is truncated")
                    }
                    val cipher = aesGcmCipher(
                        Cipher.DECRYPT_MODE,
                        key,
                        chunkNonce(header.baseNonce, index),
                    )
                    // doFinal verifies this chunk's tag before returning bytes.
                    output.write(cipher.doFinal(payload))
                    remaining -= thisLength
                    index++
                }
            }
        }
        Log.i(TAG, "Decrypted(v2): ${inputFile.path} -> ${outputFile.path} (${outputFile.length()} bytes)")
        return mapOf("ok" to true, "plaintextSize" to outputFile.length())
    }

    /** Decrypt to a ByteArray (small files / in-memory use). */
    fun decryptFileToBytes(
        filePath: String,
        dek: ByteArray,
    ): Map<String, Any?> {
        val inputFile = File(filePath)
        if (!inputFile.exists()) {
            return mapOf("ok" to false, "error" to "File not found: $filePath")
        }
        // Safety limit: don't load > 512 MiB into memory
        if (inputFile.length() > 512L * 1024 * 1024) {
            return mapOf("ok" to false, "error" to "File too large for in-memory decryption, use file output instead")
        }

        return try {
            if (isV2(inputFile)) decryptV2ToBytes(inputFile, dek)
            else decryptV1ToBytes(inputFile, dek)
        } catch (e: OutOfMemoryError) {
            Log.e(TAG, "DecryptToBytes ran out of memory: $filePath", e)
            mapOf("ok" to false, "error" to "Out of memory while decrypting: file too large")
        } catch (e: javax.crypto.AEADBadTagException) {
            mapOf("ok" to false, "error" to "Authentication failed: file may be corrupted or tampered with")
        } catch (e: Exception) {
            Log.e(TAG, "DecryptToBytes failed: $filePath", e)
            mapOf("ok" to false, "error" to (e.message ?: "Unknown error"))
        }
    }

    /** v2 path for [decryptFileToBytes]: decrypted chunk by chunk. */
    private fun decryptV2ToBytes(inputFile: File, dek: ByteArray): Map<String, Any?> {
        val header = readV2Header(inputFile)
            ?: return mapOf("ok" to false, "error" to "Invalid encrypted file format")
        val key = SecretKeySpec(dek, "AES")
        val plaintext = java.io.ByteArrayOutputStream(
            minOf(header.plaintextSize, 8L * 1024 * 1024).toInt(),
        )
        FileInputStream(inputFile).use { input ->
            if (!skipFully(input, V2_HEADER_SIZE.toLong())) {
                return mapOf("ok" to false, "error" to "Invalid encrypted file format")
            }
            var remaining = header.plaintextSize
            var index = 0
            while (remaining > 0) {
                val thisLength = minOf(remaining, header.chunkSize.toLong()).toInt()
                val payload = ByteArray(thisLength + GCM_TAG_LENGTH / 8)
                if (!readFully(input, payload)) {
                    return mapOf("ok" to false, "error" to "Encrypted file is truncated")
                }
                val cipher = aesGcmCipher(
                    Cipher.DECRYPT_MODE,
                    key,
                    chunkNonce(header.baseNonce, index),
                )
                plaintext.write(cipher.doFinal(payload))
                remaining -= thisLength
                index++
            }
        }
        val bytes = plaintext.toByteArray()
        return mapOf("ok" to true, "bytes" to bytes, "plaintextSize" to bytes.size)
    }

    /** v1 path for [decryptFileToBytes] (legacy single GCM stream). */
    private fun decryptV1ToBytes(inputFile: File, dek: ByteArray): Map<String, Any?> {
        val fileLength = inputFile.length()
        // Same 28-byte floor as decryptFile: nonce + tag only.
        val minLength = GCM_NONCE_LENGTH + GCM_TAG_LENGTH / 8
        if (fileLength < minLength) {
            return mapOf("ok" to false, "error" to "File too small to be encrypted: $fileLength bytes")
        }
        val fileBytes = inputFile.readBytes()
        val nonce = fileBytes.copyOfRange(0, GCM_NONCE_LENGTH)
        // Everything after the nonce is ciphertext followed by the 16-byte tag.
        val body = fileBytes.copyOfRange(GCM_NONCE_LENGTH, fileBytes.size)
        if (body.size < GCM_TAG_LENGTH / 8) {
            return mapOf("ok" to false, "error" to "Invalid encrypted file format")
        }
        val key = SecretKeySpec(dek, "AES")
        val cipher = aesGcmCipher(Cipher.DECRYPT_MODE, key, nonce)
        val plaintext = cipher.doFinal(body)
        return mapOf("ok" to true, "bytes" to plaintext, "plaintextSize" to plaintext.size)
    }
}