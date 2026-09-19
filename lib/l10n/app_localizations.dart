


/// Chinese strings for Privi.
class AppLocalizations {
  const AppLocalizations._();

  static const AppLocalizations current = AppLocalizations._();

  String get appName => 'Privi';

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

  String get photosOnlyTapVideos => '仅照片 · 点按切换视频';

  String get videosOnlyTapPhotos => '仅视频 · 点按切换照片';

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

  String get permissionNeededBody => 'Privi 需要权限才能从系统图库隐藏照片和视频。请在设置中允许后重试。';

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

  String get noPhotoFolders => '未找到照片文件夹';

  String get noVideoFolders => '未找到视频文件夹';

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

  String get noPhotosInFolder => '此文件夹中没有照片';

  String get noVideosInFolder => '此文件夹中没有视频';

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
      '请使用手机的指纹、面容或屏幕锁验证身份，然后可绘制新的保险库图案。\n\n媒体仍保留在设备上；仅重置保险库解锁图案。';

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

  String get diagnosticLogEnabled => '已开启 · 写入 Download/Privi/logs';

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

  String get externalPlaybackUnsupported => '外部播放不可用';

  String get shuffleByDefault => '默认随机播放';

  String get slideshowDelay => '幻灯片间隔';

  String get recycleRetention => '回收站保留时间';

  String get vaultSize => '保险库大小';

  String get exportVault => '导出保险库…';

  String get exportVaultSubtitle => '将媒体与元数据导出到文件夹';

  String get importVault => '导入保险库…';

  String get importVaultSubtitle => '从先前的导出文件夹导入';

  String get backupExportPickerTitle => '选择备份文件夹';

  String get backupRestorePickerTitle => '选择备份文件夹';

  String get backupExportProgressTitle => '导出保险库';

  String get backupRestoreProgressTitle => '恢复保险库';

  String get backupExportCompleteTitle => '备份已验证';

  String get backupRestoreCompleteTitle => '恢复完成';

  String get backupExportErrorTitle => '导出失败';

  String get backupRestoreErrorTitle => '恢复失败';

  String get backupCancelledTitle => '已取消';

  String get backupCancelledBody => '未保存任何更改。';

  String get backupCancelling => '正在完成当前文件…';

  String get backupStagePreparing => '正在准备';

  String get backupStageCheckingSource => '正在检查源文件';

  String get backupStageCopying => '正在复制媒体';

  String get backupStageWritingManifest => '正在写入清单';

  String get backupStageCheckingBackup => '正在检查备份';

  String get backupStageRestoring => '正在恢复媒体';

  String get backupStageComplete => '已完成';

  String get backupProgressLabel => '备份进度';

  String backupProgressCount(int completed, int total) {
    return '$completed / $total';
  }

  String backupItemCount(int count) {
    return '$count 项';
  }

  String get backupChecksumVerified => '已检查 SHA-256';

  String get backupCheckedWithoutChecksum => '文件已检查 · 无校验值';

  String get backupUnknownItem => '未知项目';

  String get backupFolderSelectionFailed => '无法打开文件夹，请重试';

  String get backupManifestMissing => '未找到 Privi 备份清单。';

  String get backupManifestMalformed => '备份清单无效。';

  String backupManifestMalformedItem(String name) {
    return '清单项目无效：$name';
  }

  String get backupVersionUnsupported => '不支持此备份版本。';

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

  String get backupExportWriteFailed => '无法写入备份，请检查文件夹权限和剩余空间。';

  String get backupRestoreWriteFailed => '无法恢复备份，请检查存储权限和剩余空间。';

  String get backupExportFailedGeneric => '导出失败，请检查源文件后重试。';

  String get backupRestoreFailedGeneric => '恢复失败，请检查备份后重试。';

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
    return 'GitHub 已发布 Privi $version';
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

  String get doubleTapSeek => '双击跳转';

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

  String get unlockPrivi => '解锁 Privi';

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

  String get confirmResetPattern => '确认身份以重置 Privi 图案';

  String get wrongPattern => '图案错误';

  String get wrongPin => 'PIN 错误';

  String get noSystemLock => '请先在 Android 设置中启用屏幕锁定';

  String get systemAuthCancelled => '系统验证已取消';

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
}