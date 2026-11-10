/// Chinese strings for 密册.
class AppLocalizations {
  const AppLocalizations._();

  static const AppLocalizations current = AppLocalizations._();

  String get appName => '密册';

  String get visible => '可见';

  String get invisible => '私密';

  String get settings => '设置';

  String get more => '更多';

  String get cancel => '取消';

  String get save => '保存';

  String get create => '创建';

  String get continueAction => '继续';

  String get enable => '启用';

  String get notNow => '暂不';

  String get close => '关闭';

  String get retry => '重试';

  String get done => '完成';

  String get next => '下一步';

  String get clear => '清除';

  String get select => '选择';

  /// 媒体项滑出后右侧的「操作」按钮（打开与长按相同的菜单）。
  String get actions => '操作';

  String get selectAll => '全选';

  String get search => '搜索';

  String get searchNameHint => '搜索名称…';

  String get closeSearch => '关闭搜索';

  String get sort => '排序';

  String get multiSort => '多重排序';

  String get style => '样式';

  String get layoutStyle => '布局样式';

  String columnsCount(int count) {
    return '$count 列';
  }

  String get multiSelectItems => '多选项目';

  String get photosOnly => '仅照片';

  String get videosOnly => '仅视频';

  String get newAlbum => '新建相册';

  String get newVaultAlbum => '新建私密相册';

  String get albumNameHint => '相册名称';

  String get rename => '重命名';

  String get renameAlbum => '重命名相册';

  String get deleteAlbum => '删除相册';

  String get deleteAlbumSubtitle => '媒体仍保留在“全部媒体”中';

  String get shuffle => '随机播放';

  String get restore => '还原';

  String get restoreAlbumTitle => '还原相册？';

  String restoreAlbumBody(int count, String name) {
    return '将“$name”中的 $count 项取消隐藏并还原到系统图库。';
  }

  String get unhideAllInAlbum => '还原此相册中的全部项目';

  String get pinToTop => '置顶';

  String get unpin => '取消置顶';

  String get pinnedToTop => '已置顶';

  String get unpinned => '已取消置顶';

  String get noMediaToPlay => '没有可播放的媒体';

  String get nothingToRestore => '没有可还原的内容';

  String restoredItems(int count) {
    return '已还原 $count 项';
  }

  String itemsCount(int count) {
    return '$count 项';
  }

  String errorWithDetails(String error) {
    return '错误：$error';
  }

  String get hide => '隐藏';

  String get hiding => '正在隐藏…';

  String get resolvingMedia => '正在准备媒体…';

  String get unhiding => '正在取消隐藏…';

  String hidingParallel(int workers) {
    return '正在隐藏（×$workers）…';
  }

  String get hideFolderTitle => '隐藏文件夹？';

  String hideFolderBody(String name, int count) {
    return '将“$name”中的媒体从系统图库隐藏（共 $count 项）。';
  }

  String get moveFolderToVault => '将此文件夹移入私密保险库';

  String get permissionNeeded => '需要权限';

  String get permissionNeededBody => '密册需要权限才能从系统图库隐藏照片和视频。请在设置中允许后重试。';

  String get openSettings => '打开设置';

  String get openSystemSettings => '打开系统设置';

  String get grantPermission => '授予权限';

  String get allowGalleryAccess => '允许访问图库';

  String get allowGalleryAccessBody => '“可见”会列出你的照片或视频文件夹。请授予权限以便浏览和隐藏。';

  String get limitedPhotosAccess => '仅可访问已选择的照片';

  String get mediaNotAvailableOffline => '原始媒体尚未下载到本机';

  String get sourceStillPresent => '私密副本已保存，原件仍在照片中';

  String get privateCopyVerificationFailed => '无法验证私密副本';

  String get operationUnavailableOnPlatform => '当前平台不支持此操作';

  String get noMediaFolders => '未找到媒体文件夹';

  String couldNotLoadGallery(String error) {
    return '无法加载图库：$error';
  }

  String get noMediaToHide => '没有可隐藏的媒体';

  String get couldNotOpenFilesToHide => '无法打开要隐藏的文件';

  String get couldNotOpenPathsToRename => '无法打开要重命名的文件路径。';

  String get couldNotHideMedia => '无法隐藏媒体，请重试。';

  String get nothingHidden => '未隐藏任何内容';

  String hiddenToAlbum(String name) {
    return '已隐藏 → 私密 / $name';
  }

  String hiddenCountToAlbum(int count, String name) {
    return '已隐藏 $count 项 → 私密 / $name';
  }

  String hiddenSharedItems(int count) {
    return '已隐藏 $count 个分享项';
  }

  String get unlockToHideShared => '解锁后即可隐藏分享的媒体';

  String get unhide => '取消隐藏';

  String unhiddenItems(int count) {
    return '已取消隐藏 $count 项';
  }

  String get share => '分享';

  String get delete => '删除';

  String get deleteFromDeviceTitle => '从设备删除？';

  String deleteFromDeviceBody(int count) {
    return '将从系统图库永久删除 $count 项。此操作无法撤销。';
  }

  String deleteFailed(String error) {
    return '删除失败：$error';
  }

  String get noItemsDeleted => '未删除任何项目';

  String deletedItems(int count) {
    return '已删除 $count 项';
  }

  String selectedCount(int count) {
    return '已选 $count 项';
  }

  String get noMatches => '无匹配结果';

  String get noMediaInFolder => '此文件夹中没有媒体';

  String get playPlaylist => '播放列表';

  String get playPlaylistShuffleOn => '以随机播放开始？';

  String get playPlaylistShuffleOff => '以顺序播放开始？可在播放器中切换。';

  String get inOrder => '顺序';

  String get noExternalPlayer => '未找到外部播放器 — 改用应用内播放';

  String get openedExternalPlayer => '已在外部打开';

  String get rate => '评分';

  String get details => '详情';

  String get moveToAlbum => '移到相册';

  String get moveToRecycleBin => '移到回收站';

  String get deleteForever => '永久删除';

  String get setAsCover => '设为封面';

  String get coverUpdated => '封面已更新';

  String get unhideRestoreOriginal => '取消隐藏（还原原始名称）';

  String restoredCount(int count) {
    return '已还原 $count';
  }

  String movedToRecycleBinCount(int count) {
    return '已将 $count 项移到回收站';
  }

  String deletedForeverCount(int count) {
    return '已永久删除 $count 项';
  }

  String movedToAlbumCount(int count) {
    return '已将 $count 项移到相册';
  }

  String get createUserAlbumFirst => '请先创建用户相册';

  String get createAnotherAlbumFirst => '请先创建另一个相册';

  String get noMediaYet => '暂无媒体';

  String get noFavoritesYet => '暂无收藏';

  String get recycleBinEmpty => '回收站为空';

  String get noFavoritesHint => '长按媒体并用爱心评分。';

  String get recycleEmptyHint => '软删除的项目会出现在这里。';

  String get noMediaHint => '从“可见”标签隐藏媒体。';

  String get favorites => '收藏';

  String get allMedia => '全部媒体';

  String get recycleBin => '回收站';

  String get hearts => '爱心';

  String get unrated => '未评分';

  String get all => '全部';

  String get emptyRecycleBin => '清空回收站';

  String get emptyRecycleBinTitle => '清空回收站？';

  String get emptyRecycleBinBody => '永久删除所有软删除项目。';

  String purgedItems(int count) {
    return '已清理 $count 项';
  }

  String get purgeItemTitle => '永久删除？';

  String get purgeItemBody => '此操作不可撤销，确定要永久删除吗？';

  String get sortNewestFirst => '最新优先';

  String get sortOldestFirst => '最早优先';

  String get sortNameAsc => '名称 A–Z';

  String get sortNameDesc => '名称 Z–A';

  String get sortHighestRating => '评分从高到低';

  String get sortLowestRating => '评分从低到高';

  String get albumSortNewest => '相册从新到旧';

  String get albumSortOldest => '相册从旧到新';

  String get albumSortCustom => '自定义顺序';

  String get arrangeOrder => '整理顺序';

  String get listView => '列表';

  String get mosaicView => '马赛克';

  String get unsavedChanges => '尚未保存';

  String get discardChanges => '放弃';

  String get unsavedChangesBody => '放弃新的顺序？';

  String get orderSaved => '顺序已保存';

  String get addToGroup => '加入合集';

  String get newGroup => '新建合集';

  String get manageGroup => '管理合集';

  String get addAlbums => '添加相册';

  String get noAlbumsToAdd => '没有可添加的相册';

  String addedAlbums(int count) {
    return '已添加 $count 个相册';
  }

  String get removedFromGroup => '已移出合集';

  String get newGroupCreated => '合集已创建';

  String get groupNameHint => '合集名称';

  String get renameGroup => '重命名合集';

  String get dissolveGroup => '解散合集';

  String get dissolveGroupBody => '相册将回到主页，不会删除任何内容。';

  String get removeFromGroup => '移出合集';

  String get emptyGroup => '暂无相册';

  String albumsCount(int count) {
    return '$count 个相册';
  }

  String sortsCount(int count) {
    return '$count 项排序';
  }

  String progressOkSkipFail(int imported, int skipped, int failed) {
    return '成功 $imported · 跳过 $skipped · 失败 $failed';
  }

  String failedItems(int count) {
    return '失败 $count 项';
  }

  String get drawPattern => '绘制图案';

  String get confirmPattern => '确认图案';

  String get redrawPattern => '重新绘制图案';

  String get drawYourPattern => '绘制你的图案';

  String get enterYourPin => '输入 PIN';

  String get connectAtLeast4Dots => '至少连接 4 个点';

  String get unlockWithBiometric => '使用生物识别解锁';

  String get forgotPattern => '忘记图案？';

  String get forgotPatternTitle => '忘记图案？';

  String get forgotPatternBody =>
      '请使用手机的指纹、面容或屏幕锁验证身份，然后可绘制新的保险库图案。\n\n⚠️ 重置图案后，已加密的媒体文件将永久无法解密。请先将加密文件还原到相册再操作。';

  String get enableBiometricTitle => '启用生物识别解锁？';

  String get enableBiometricBody => '使用指纹或面容更快解锁。图案仍可作为备用解锁方式。';

  String get biometricNotEnabled => '未启用生物识别 — 可在设置中重试';

  String get patternsDidNotMatch => '图案不匹配 — 请重试';

  String get drawNewPatternProtect => '绘制新图案以保护保险库';

  String get sectionSecurity => '安全';

  String get sectionDisplay => '显示';

  String get sectionPlayback => '播放';

  String get sectionStorage => '存储';

  String get sectionAbout => '关于';

  String get sectionDiagnostics => '诊断';

  String get diagnosticLog => '记录诊断日志';

  String get diagnosticLogEnabled => '已开启 · 写入 Download/密册/logs';

  String get diagnosticLogDisabled => '已关闭 · 不再写入任何日志';

  String get lockNow => '立即锁定';

  String get changePattern => '更改图案';

  String get rootUnlockCredential => '主解锁凭据';

  String get biometricUnlock => '生物识别解锁';

  String get autoLock => '自动锁定';

  String get autoLockImmediately => '立即';

  String autoLockSeconds(int seconds) {
    return '$seconds 秒';
  }

  String autoLockMinutes(int minutes) {
    return '$minutes 分钟';
  }

  String autoLockMinutesPlural(int minutes) {
    return '$minutes 分钟';
  }

  String get blockScreenshots => '阻止截屏';

  String get blockScreenshotsSubtitle => 'FLAG_SECURE — 在最近任务中隐藏内容';

  String get protectAppPreview => '保护后台预览';

  String get protectAppPreviewSubtitle => '隐藏后台预览，不阻止截屏';

  String get mediaGridColumns => '默认网格列数';

  String get albumColumns => '相册列数';

  String get preferExternalPlayer => '优先使用外部播放器';

  String get inAppPlayback => '应用内播放';

  /// 长按视频的「打开方式」：用设置里选定的引擎在本应用内播放。
  String get inAppPlaybackDefaultEngine => '内部播放（默认引擎）';

  /// 长按视频的「打开方式」：本次强制用 libVLC 引擎在本应用内播放
  /// （默认引擎解不了的片子走这条）。
  String get inAppPlaybackVlcEngine => '内部播放（VLC 引擎）';

  String get externalPlaybackUnsupported => '外部播放不可用';

  String get playerEngine => '播放引擎';

  String get playerEngineExoPlayer => 'ExoPlayer（系统解码器）';

  String get playerEngineVlc => 'libVLC（FFmpeg 解码，格式更全）';

  String get shuffleByDefault => '默认随机播放';

  /// 随机播放与播放记录（去重）——顶部标签。
  String get shufflePlayCount => '按播放次数随机';

  String get shufflePlayCountOff => '关闭（完全随机）';

  String get shufflePlayCountSoften => '播放越多，概率越低';

  String get shufflePlayCountSkip => '达到次数后基本不出现';

  String get shuffleSkipThreshold => '不出现的播放次数';

  String shuffleSkipAtLeast(int count) {
    return '播放满 $count 次后';
  }

  String playCountTimes(int count) {
    return '已播放 $count 次';
  }

  String get clearPlayHistory => '清除播放记录';

  String get clearPlayHistorySubtitle => '所有媒体重新回到等概率随机';

  String playHistoryCleared(int count) {
    return count > 0 ? '已清除 $count 项播放记录' : '没有可清除的播放记录';
  }

  String get playCountLabel => '播放次数';

  String get lastPlayedLabel => '最近播放';

  String get slideshowDelay => '幻灯片间隔';

  String get recycleRetention => '回收站保留时间';

  String get vaultSize => '保险库大小';

  /// 合并后的功能名：保险库数据（Vault Data）。「数据」= 记录、相册、
  /// 密钥和设置，媒体文件本体不在其中，需单独拷贝。
  String get exportVault => '导出保险库数据…';

  String get exportVaultSubtitle => '把记录、相册、密钥和设置存成一份数据文件；不含媒体文件';

  String get importVault => '导入保险库数据…';

  String get importVaultSubtitle => '从数据文件恢复；媒体文件请先单独拷贝回保险库目录';

  String get backupExportWarning => '导出会保存全部媒体记录、相册、加密密钥和应用设置，'
      '但不会包含媒体文件本体（它们已保存在手机存储里，请单独拷贝）。\n\n'
      '⚠️ 数据文件里含有「未加密」的保险库密钥：任何同时拿到数据文件与保险库目录的人'
      '都能解密全部文件。请放到加密网盘或离线介质，不要分享给别人。\n\n继续导出？';

  String get backupImportWarning => '导入会恢复记录、相册、设置，并把其中的加密密钥'
      '登记为额外密钥，不会覆盖本机当前密钥。\n\n'
      '媒体文件不在数据文件里：请先把它们（保持原文件名）单独拷贝到本应用的保险库目录，'
      '导入时会按文件名自动匹配；找不到文件的条目会被跳过。\n\n继续导入？';

  String get backupExportPickerTitle => '选择数据存放文件夹';

  String get backupRestorePickerTitle => '选择数据所在文件夹';

  String get backupExportProgressTitle => '导出保险库数据';

  String get backupRestoreProgressTitle => '恢复保险库数据';

  String get backupExportCompleteTitle => '数据已验证';

  String get backupRestoreCompleteTitle => '数据恢复完成';

  String get backupExportErrorTitle => '导出失败';

  String get backupRestoreErrorTitle => '恢复失败';

  String get backupCancelledTitle => '已取消';

  String get backupCancelledBody => '未保存任何更改。';

  String get backupCancelling => '正在收尾…';

  String get backupStagePreparing => '正在准备';

  String get backupStageCheckingSource => '正在读取数据';

  String get backupStageCopying => '正在整理数据';

  String get backupStageWritingManifest => '正在写入清单';

  String get backupStageCheckingBackup => '正在检查数据';

  String get backupStageRestoring => '正在恢复数据';

  String get backupStageComplete => '已完成';

  String get backupProgressLabel => '数据进度';

  String backupProgressCount(int completed, int total) {
    return '$completed / $total';
  }

  String backupItemCount(int count) {
    return '$count 项';
  }

  String get backupChecksumVerified => '已验证数据内容';

  String get backupCheckedWithoutChecksum => '已读取数据内容 · 无校验值';

  String get backupUnknownItem => '未知项目';

  String get backupFolderSelectionFailed => '无法打开文件夹，请重试';

  String get backupManifestMissing => '未找到密册数据清单。';

  String get backupManifestMalformed => '数据清单无效。';

  String backupManifestMalformedItem(String name) {
    return '清单项目无效：$name';
  }

  String get backupVersionUnsupported => '不支持此数据版本。';

  String backupSourceMissing(String name) {
    return '源文件缺失：$name';
  }

  String backupSourceUnreadable(String name) {
    return '无法读取源文件：$name';
  }

  String backupSourceEmpty(String name) {
    return '源文件为空：$name';
  }

  String backupSourceChanged(String name) {
    return '导出期间源文件发生变化：$name';
  }

  String backupPayloadMissing(String name) {
    return '备份文件缺失：$name';
  }

  String backupPayloadUnreadable(String name) {
    return '无法读取备份文件：$name';
  }

  String backupPayloadEmpty(String name) {
    return '备份文件为空：$name';
  }

  String backupPayloadLengthMismatch(String name) {
    return '备份文件大小不符：$name';
  }

  String backupPayloadDigestMismatch(String name) {
    return '备份文件校验值不符：$name';
  }

  String backupUnsafePath(String name) {
    return '备份路径不安全：$name';
  }

  String backupDestinationConflict(String name) {
    return '请选择空文件夹。已有项目：$name';
  }

  String get backupExportWriteFailed => '无法写入数据文件，请检查文件夹权限和剩余空间。';

  String get backupRestoreWriteFailed => '无法恢复数据，请检查存储权限和剩余空间。';

  String get backupExportFailedGeneric => '导出失败，请检查保险库数据后重试。';

  String get backupRestoreFailedGeneric => '恢复失败，请检查数据文件后重试。';

  String get encryptExistingFiles => '加密已有文件';

  String get encryptExistingFilesSubtitle => '加密保险库中尚未加密的媒体文件';

  String get vaultLockedPleaseUnlock => '保险库已锁定，请先解锁。';

  String get allFilesAlreadyEncrypted => '所有文件已加密。';

  String get encryptionSkippedVaultLocked =>
      '文件已移入保险库，但密钥未就绪、未能加密。请解锁后到「设置 → 加密已有文件」补加密。';

  String encryptConfirmationBody(int count) {
    return '$count 个文件将被加密。此操作在保险库锁定期间不可撤销。确定继续？\n\n'
        '⚠️ 加密密钥只保存在本机：卸载应用或清除应用数据后，已加密文件将无法解密。'
        '请先做好备份（或先把加密文件还原到相册）。';
  }

  String get encryptAction => '加密';

  String get vaultLockedOperationStopped => '保险库已锁定，操作已停止。';

  String get encryptingTitle => '正在加密…';

  // ── "Encrypt existing files" options (content + file name) ──

  /// Checkbox 1 of the confirmation dialog.
  String get encryptOptionContent => '加密文件内容';

  String encryptOptionContentSubtitle(int count) =>
      count > 0 ? '还有 $count 个文件的内容是明文' : '所有文件的内容都已加密';

  /// Checkbox 2: renames ciphertext files to random, extension-less names.
  String get encryptOptionFilenames => '加密文件名';

  String encryptOptionFilenamesSubtitle(int count) => count > 0
      ? '有 $count 个已加密文件仍保留原文件名（含扩展名）'
      : '所有已加密文件的文件名都已加密';

  String get encryptOptionsPickOne => '请至少选择一项';

  /// Body shown when the only selected work is the filename pass.
  String encryptFilenamesConfirmationBody(int count) =>
      '将把 $count 个已加密文件的文件名改成不含扩展名的随机名，避免被"按扩展名扫描"的程序认出来。\n'
      '原文件名仍保存在应用内：查看、播放、还原到相册时都不变。\n\n继续？';

  String renamingProgress(int current, int total) =>
      '正在加密文件名，第 $current 项（共 $total 项）…';

  String filenameEncryptResult(int count) => '已加密 $count 个文件名。';

  String filenameEncryptFailedCount(int count) => '$count 个文件名加密失败';

  String filenameEncryptSkippedCount(int count) =>
      '$count 个文件名已是加密文件名（跳过）';

  // ── "Decrypt all files" options (content + file name) ──

  String get decryptAllFiles => '解密所有文件';
  String get decryptAllFilesSubtitle =>
      '把保险库里的密文解密为明文（与"加密已有文件"相反）';

  String get decryptOptionContent => '解密文件内容';

  String decryptOptionContentSubtitle(int count) =>
      count > 0 ? '有 $count 个密文文件将被解密为明文' : '没有需要解密的密文';

  String get decryptOptionFilenames => '解密文件名';

  String decryptOptionFilenamesSubtitle(int count) => count > 0
      ? '有 $count 个随机文件名将恢复为原文件名'
      : '没有需要恢复的文件名';

  String get decryptConfirmationBody =>
      '解密后文件会以明文保存在保险库目录里，只靠"隐藏目录"保护，安全性低于加密状态。\n'
      '需要时可以用「加密已有文件」重新加密。\n\n继续解密？';

  String get decryptFilenamesOnlyBody =>
      '将把随机文件名恢复为原始文件名（原名保存在应用内），文件内容保持加密状态。\n\n继续？';

  String get decryptingTitle => '正在解密…';

  String decryptingProgress(int current, int total) =>
      '正在解密，第 $current 项（共 $total 项）…';

  String restoringNamesProgress(int current, int total) =>
      '正在恢复文件名，第 $current 项（共 $total 项）…';

  String decryptResultSuccess(int count) => '已解密 $count 个文件。';

  String decryptResultPartial(int decrypted, int failed) =>
      '已解密 $decrypted 个文件，$failed 个失败。';

  String get decryptNothingToDo => '没有需要解密的文件';

  String filenameRestoreResult(int count) => '已恢复 $count 个文件名。';

  String filenameRestoreFailedCount(int count) => '$count 个文件名恢复失败';

  // ── Encryption record repair ("clear failed records") ──

  String get repairEncryptionRecords => '修复加密记录';
  String get repairEncryptionRecordsSubtitle =>
      '清除"记录了已加密、实际仍是明文"的失效记录';

  String get scanningEncryptionRecords => '正在检查加密记录…';

  String repairEncryptionRecordsBody(int count) =>
      '发现 $count 条失效记录：应用以为这些文件已加密，但文件实际仍是明文。\n'
      '清除后它们会重新出现在「加密已有文件」的待加密列表里。\n\n继续？';

  String repairEncryptionResult(int cleared) => '已清除 $cleared 条失效记录。';

  String repairEncryptionOrphans(int count) =>
      '另有 $count 个文件是密文但没有密钥记录：既无法解密也无法再加密，请从备份找回或删除。';

  String get repairEncryptionNothingFound => '没有发现失效记录。';

  String get repairEncryptionFailed => '修复失败，请重试。';

  // ── Crypto repair for a **selection** (Visible / Invisible grid capsule) ──

  /// Selection-capsule action: try to make the selected files consistent with
  /// their encryption records (see `MediaCryptoRepairService`).
  String get repairCrypto => '加解密修复';

  String get repairCryptoRunning => '正在修复加密状态…';

  String repairCryptoProgress(int current, int total, String name) =>
      '第 $current / $total 项：$name';

  String get repairCryptoNothingSelected => '请先选择要修复的文件。';

  String get repairCryptoPathsUnresolved =>
      '没能定位到所选文件的真实路径，无法修复（可改用「私密」里同一文件重试）。';

  String get repairCryptoLocked => '保险库已锁定：请先解锁密册再修复密文文件。';

  String repairCryptoDecrypted(int count) => '已解密 $count 个文件，现在可以正常查看。';

  String repairCryptoRecordCleared(int count) =>
      '已清除 $count 条失效加密记录（文件本身是明文，之前被误判成密文）。';

  String repairCryptoKeyMismatch(int count) =>
      '$count 个文件没能解密：记录里的密钥与文件内容不匹配（该文件很可能被另一把密钥加密过）。'
      '文件保持原样，未做任何修改。';

  String repairCryptoNoKey(int count) => '$count 个文件是密文但没有密钥记录：无法解密，请从备份恢复或删除。';

  String repairCryptoMissing(int count) =>
      '$count 个文件在保险库里已不存在（可能已被移到可见相册：请在那里选中它再修复一次）。';

  String repairCryptoFailed(int count) => '$count 个文件修复失败，详情见应用日志。';

  String get repairCryptoAlreadyPlain => '所选文件是明文且没有加密记录，无需修复。';

  String encryptingProgress(int current, int total) {
    return '正在加密，第 $current 项（共 $total 项）…';
  }

  String encryptFailedCount(int count) {
    return '$count 项失败';
  }

  /// Files whose media is already ciphertext but whose DEK is missing: they can
  /// neither be encrypted again nor decrypted (ISSUE-030).
  String encryptSkippedNoKey(int count) {
    return '$count 个文件已是密文但没有密钥记录：无法再加密、也无法解密，请从备份恢复或删除';
  }

  /// Rows whose media file has disappeared (maintenance removes them).
  String encryptMissingFiles(int count) {
    return '$count 条记录对应的文件已不存在（下次启动会自动清理）';
  }

  String encryptResultSuccess(int count) {
    return '已成功加密 $count 个文件。';
  }

  String encryptResultPartial(int completed, int failed) {
    return '已加密 $completed 个文件，$failed 个失败。';
  }

  String get scanOrphans => '扫描孤立隐藏文件';

  String get scanningOrphans => '正在扫描孤立隐藏文件…';

  String get recoverVault => '重装后恢复保险库';

  String get recoverVaultSubtitle => '重新索引仍在 .privateheart_vault 中的媒体';

  String get recoverVaultBody =>
      '扫描磁盘上的保险库文件夹，把缺失项带回 Invisible。卸载重装后文件仍在手机上时使用。';

  String get recoverAndUnhide => '恢复并还原到图库';

  String get recoverAndUnhideSubtitle => '重新索引保险库文件并取消隐藏';

  String get recoverAndUnhideBody =>
      '重新索引保险库文件夹中的文件，再移回公共目录（下载/已知原路径）。重装后若希望图库再次可见时使用。';

  String get recoveringVault => '正在恢复保险库文件…';

  String get repairCaptureDates => '修复拍摄日期';

  String get repairCaptureDatesSubtitle => '按原始拍摄时间修正保险库排序（非隐藏时间）';

  String get repairingCaptureDates => '正在修复拍摄日期…';

  String get author => '作者';

  String get license => '许可证';

  String get couldNotOpenBrowser => '无法打开浏览器';

  String versionLabel(String version) {
    return '版本 $version';
  }

  String patchLabel(int number) {
    return '补丁 $number';
  }

  String get checkUpdates => '检查更新';

  String get updateAvailableTitle => '有可用更新';

  String get updateDownloadPrompt => '立即下载并重启？';

  String get updateDownloadRelaunchPrompt => '立即下载？重新打开后生效。';

  String appReleasePrompt(String version) {
    return 'GitHub 已发布密册 $version';
  }

  String get later => '稍后';

  String get updateAction => '更新';

  String get viewRelease => '查看';

  String get upToDate => '已是最新版本';

  String get updateRestartFailed => '重启失败，请重新打开';

  String get updateRelaunchRequired => '更新已下载，请重新打开应用';

  String get updatesUnavailable => '此版本不支持更新';

  String get updateCheckFailed => '检查失败';

  String get updateDownloadFailed => '更新失败';

  String authorLabel(String author) {
    return '作者：$author';
  }

  String scanFailed(String error) {
    return '扫描失败：$error';
  }

  String get playing => '正在播放';

  String get emptyPlaylist => '播放列表为空';

  String get openExternal => '外部打开';

  String get previousMedia => '上一项';

  String get nextMedia => '下一项';

  String get play => '播放';

  String get pause => '暂停';

  String get portrait => '竖屏';

  String get landscape => '横屏';

  String get videoDisplayMode => '画面比例';

  String get videoFit => '适应';

  String get videoFill => '铺满';

  String get videoOriginal => '原始';

  String get videoRatioFourThree => '4:3';

  String get videoRatioSixteenNine => '16:9';

  String get playerSettings => '播放设置';

  /// 播放区横向滑动的步长：滑过一档就前进/后退这么多秒。
  String get seekStepSeconds => '快进/快退步长';

  /// 播放区右滑（快进）时画面中央的提示。
  String get fastForward => '快进';

  /// 播放区左滑（快退）时画面中央的提示。
  String get rewind => '快退';

  String get playbackSpeed => '播放速度';

  String get mute => '静音';

  String get loopVideo => '循环播放';

  String get typeLabel => '类型';

  String get typeVideo => '视频';

  String get typeImage => '图片';

  String get nameLabel => '名称';

  String get sizeLabel => '大小';

  String get pathLabel => '路径';

  String get ratingLabel => '评分';

  String get currentPattern => '当前图案';

  String get newPattern => '新图案';

  String get confirmNewPattern => '确认新图案';

  String get patternUpdated => '图案已更新';

  String get newPatternsDidNotMatch => '新图案不匹配';

  String get drawCurrentPattern => '绘制当前图案以继续';

  String get drawSamePatternAgain => '请再次绘制相同图案';

  String get currentPin => '当前 PIN';

  String get enterPinThenPattern => '输入 PIN，然后设置新图案';

  String get pin => 'PIN';

  String get retention => '保留时间';

  String get language => '语言';

  String get languageSystem => '跟随系统';

  String get languageEnglish => 'English';

  String get languageZhCn => '简体中文';

  String get languageZhHk => '繁體中文（香港）';

  String get verifyIdentity => '验证身份';

  String get unlockPrivi => '解锁密册';

  String get biometricAvailable => '可用时使用指纹 / 面容';

  String get biometricUnavailable => '此设备不可用';

  String get biometricCancelled => '未启用生物识别（已取消或失败）';

  String get biometricUpdateFailed => '无法更新生物识别设置';

  String get externalPlayerSubtitle => '将视频交给 VLC / 系统播放器';

  String get scanOrphansSubtitle => '查找库中缺失的保险库文件';

  String retentionDays(int days) {
    return '$days 天';
  }

  String get retention1Day => '1 天';

  String secondsCount(int n) {
    return '$n 秒';
  }

  String secondCount(int n) {
    return '$n 秒';
  }

  String get empty => '清空';

  String get couldNotOpenExternally => '无法用外部应用打开 — 改用应用内预览';

  String get openWith => '打开方式';

  String get playVideoWith => '播放视频';

  String get calculating => '计算中…';

  String get cancelled => '已取消';

  String get restoredToGallery => '已还原到图库';

  String get couldNotUnhideFile => '无法取消隐藏文件';

  String get favoriteToggle => '收藏';

  String ratedHearts(int rating) {
    return '已评 $rating / 3 心';
  }

  String get confirmBiometricEnable => '确认以启用生物识别解锁';

  String get confirmResetPattern => '确认身份以重置密册图案';

  String get wrongPattern => '图案错误';

  String get wrongPin => 'PIN 错误';

  String get noSystemLock => '请先在 Android 设置中启用屏幕锁定';

  String get systemAuthCancelled => '系统验证已取消';

  String get biometricKekUnavailable =>
      '指纹验证通过，但加密密钥尚未就绪 —— 请先用图案解锁一次，之后指纹即可正常使用';

  String get scanFailedShort => '扫描失败';

  String get screenshotSettingFailed => '无法更新截屏保护';

  String get privacySettingFailed => '无法更新后台预览保护';

  String get noOrphanVaultFiles => '未找到保险库文件';

  String recoveryResult(int recovered, int skipped, int failed) {
    return '已恢复 $recovered · 跳过 $skipped · 失败 $failed';
  }

  String galleryRecoveryResult(int restored, int skipped, int failed) {
    return '已还原 $restored · 跳过 $skipped · 失败 $failed';
  }

  String get noVaultMediaToRepair => '没有需要修复的媒体';

  String captureDateRepairResult(int fixed, int skipped, int failed) {
    return '已修复 $fixed · 跳过 $skipped · 失败 $failed';
  }

  String unlockLockout(int seconds) {
    return '请在 $seconds 秒后重试';
  }

  // ── 保险库管理（多保险库）──

  String get vaultLibraries => '保险库管理';

  String get vaultLibrariesSubtitle => '把手机上的目录添加为保险库，多个保险库可同时存在';

  String get vaultLibraryBuiltIn => '默认保险库';

  String get vaultLibraryBuiltInSubtitle => '应用内置，不能移除';

  String get vaultLibraryCurrent => '当前使用';

  String get vaultLibrarySetCurrent => '设为当前';

  String get vaultLibrarySetCurrentDone => '已切换当前保险库';

  String get vaultLibraryAdd => '添加保险库…';

  String get vaultLibraryAddHint =>
      '选择手机上已存放媒体文件的目录，例如从旧手机拷贝来的保险库文件夹';

  String get vaultLibraryAddConfirmTitle => '添加为保险库？';

  String get vaultLibraryAddConfirmBody =>
      '该目录会被登记为保险库，并写入 .nomedia 以对系统图库隐藏。\n\n'
      '目录里的文件不会被移动或删除，原有默认保险库保持不变，两者可同时使用。';

  String get vaultLibraryAdded => '保险库已添加';

  String get vaultLibraryScanTitle => '立即扫描？';

  String get vaultLibraryScanBody =>
      '是否扫描这个目录里的媒体文件并加入保险库？已有记录不会重复导入，'
      '目录下没有数据库记录的文件会按文件名重建索引。';

  String vaultLibraryScanDone(int count) => '扫描完成，已恢复 $count 个文件';

  String get vaultLibraryRemove => '移除';

  String get vaultLibraryRemoveTitle => '移除这个保险库？';

  String get vaultLibraryRemoveBody =>
      '只取消登记并移除该目录下的媒体记录，手机里的文件不会被删除。\n\n'
      '之后重新添加该目录并扫描，即可恢复记录。';

  String vaultLibraryRemoved(int count) => '已移除保险库，取消 $count 条记录';

  String get vaultLibraryUnavailable => '目录不存在（可能来自另一台手机）';

  String get vaultLibraryEmpty => '还没有添加其它保险库';

  String get vaultLibraryHint =>
      '新隐藏的文件会保存到「当前使用」的保险库；所有保险库里的文件都会一起显示。';

  String get vaultLibraryMigrationHint =>
      '从其它手机迁移：先把旧保险库文件夹拷贝到本机，在这里添加该目录，'
      '再导入保险库数据，媒体记录会按文件名自动匹配。';

  String get vaultLibraryNameHint => '给这个保险库起个名字';

  String get vaultLibraryErrorTitle => '无法添加该目录';

  String get vaultLibraryErrEmpty => '未选择目录';

  String get vaultLibraryErrMissing => '目录不存在';

  String get vaultLibraryErrNotDirectory => '这不是一个文件夹';

  String get vaultLibraryErrUnreadable =>
      '无法读取该目录，请在系统设置中允许本应用「所有文件访问权限」';

  String get vaultLibraryErrDuplicate => '该目录已经登记为保险库';

  String get vaultLibraryErrNested =>
      '不能选择已有保险库的上级目录或子目录，否则同一个文件会被重复扫描';

  String get vaultLibraryErrReserved =>
      '请选择一个具体的文件夹，而不是存储根目录';

  String get vaultLibraryOperationFailed => '操作失败，请重试';
}
