# Покрытие основного конфига Lite

Восстановлено 137 определений. Для 22 параметров есть обращения из написанного кода потребителей. Остальные пока являются определениями хранилища либо неактивны в выбранной Lite. Обращение подтверждает подключение исходников; компиляция приложения и проверка на iPhone фиксируются отдельно в [VALIDATION.md](VALIDATION.md).

Расшифровка и экспорт описаны в [FEATURES.md](FEATURES.md); они не означают реализации всех одноимённых Android-настроек. Полный набор Lite ещё не перенесён.

| Параметр | Тип Swift | Восстановленное значение | Подключение |
|---|---|---|---|
| `translationProvider` | `Int32` | `0` | Код потребителя подключён |
| `disableNumberRounding` | `Bool` | `false` | Код потребителя подключён |
| `formatTimeWithSeconds` | `Bool` | `false` | Код потребителя подключён |
| `relativeLastSeen` | `Bool` | `false` | Только определение |
| `inAppVibration` | `Bool` | `true` | Код потребителя подключён |
| `disableNotificationDelay` | `Bool` | `false` | Только определение |
| `filterZalgo` | `Bool` | `true` | Код потребителя подключён |
| `downloadSpeedBoost` | `Int32` | `0` | Только определение |
| `uploadSpeedBoost` | `Bool` | `false` | Только определение |
| `hidePhoneNumber` | `Bool` | `false` | Код потребителя подключён (профиль/настройки; прочие поверхности не завершены) |
| `showIdAndDc` | `Int32` | `1` | Только определение |
| `hideArchiveFolder` | `Bool` | `false` | Только определение |
| `archiveOnPull` | `Bool` | `false` | Только определение |
| `disableUnarchiveSwipe` | `Bool` | `true` | Только определение |
| `doNotUseProxy` | `Int32` | `0` | Только определение |
| `customSavePath` | `String` | `"exteraGram"` | Только определение |
| `editingIconPackId` | `String?` | `null` | Только определение |
| `avatarCorners` | `Float` | `28.0` | Только определение |
| `singleCornerRadius` | `Bool` | `false` | Только определение |
| `forceSnow` | `Bool` | `false` | Только определение |
| `hideActionBarStatus` | `Bool` | `false` | Только определение |
| `centerTitle` | `Bool` | `false` | Только определение |
| `hideStories` | `Bool` | `false` | Код потребителя подключён |
| `hideFloatingButton` | `Bool` | `false` | Только определение |
| `hideDialogsSearchBar` | `Bool` | `false` | Только определение |
| `senderMiniAvatars` | `Bool` | `true` | Только определение |
| `titleText` | `Int32` | `0` | Только определение |
| `hideAllChats` | `Bool` | `false` | Только определение |
| `squareFab` | `Bool` | `true` | Только определение |
| `sectionRadius` | `Float` | `20.0` | Только определение |
| `sectionsSeparatedHeadersPreference` | `Bool` | `true` | Только определение |
| `newLoadingStyle` | `Bool` | `true` | Только определение |
| `newSliderStyle` | `Bool` | `true` | Только определение |
| `newSwitchStyle` | `Bool` | `true` | Только определение |
| `newChatHeaderStyle` | `Bool` | `false` | Только определение |
| `newNavigationBarStyle` | `Bool` | `false` | Только определение |
| `newFabStyle` | `Bool` | `false` | Только определение |
| `tabletMode` | `Int32` | `0` | Только определение |
| `useSystemFonts` | `Bool` | `true` | Только определение |
| `gooeyAvatarAnimation` | `Bool` | `true` | Только определение |
| `customThemes` | `Bool` | `true` | Только определение |
| `predictiveBackIntensity` | `Float` | `1.0` | Только определение |
| `glassMessageMenu` | `Bool` | `true` | Только определение |
| `forceBlur` | `Bool` | `false` | Только определение |
| `eventType` | `Int32` | `0` | Только определение |
| `navigationDrawer` | `Bool` | `false` | Только определение |
| `immersiveDrawerAnimation` | `Bool` | `false` | Только определение |
| `showFeedTab` | `Bool` | `false` | Только определение |
| `showFeedUnreadCounter` | `Bool` | `true` | Только определение |
| `stickerSize` | `Float` | `12.0` | Только определение |
| `replyColors` | `Bool` | `true` | Код потребителя подключён (рендерер ответов) |
| `replyEmoji` | `Bool` | `true` | Код потребителя подключён (рендерер ответов) |
| `replyBackground` | `Bool` | `true` | Код потребителя подключён (рендерер ответов) |
| `stickerShape` | `Int32` | `1` | Только определение |
| `unlimitedRecentStickers` | `Bool` | `false` | Только определение |
| `hideReactionsInPrivateChats` | `Bool` | `false` | Код потребителя подключён |
| `hideReactionsInChannels` | `Bool` | `false` | Код потребителя подключён |
| `hideReactionsInGroups` | `Bool` | `false` | Код потребителя подключён |
| `swipeActions` | `String` | `"2"` | Только определение |
| `swipeActionsLoop` | `Bool` | `false` | Только определение |
| `swipeActionsReversed` | `Bool` | `false` | Только определение |
| `bottomButton` | `Int32` | `2` | Только определение |
| `widePostsInFeed` | `Bool` | `true` | Только определение |
| `widePostsInChannels` | `Bool` | `false` | Только определение |
| `telegramAiEditor` | `Bool` | `true` | Только определение |
| `telegramAiSummaries` | `Bool` | `true` | Только определение |
| `telegramAiInstantViewSummaries` | `Bool` | `true` | Только определение |
| `quickAdminShortcuts` | `Bool` | `true` | Только определение |
| `quickTransitionForChannels` | `Bool` | `true` | Только определение |
| `quickTransitionForTopics` | `Bool` | `true` | Только определение |
| `disableGreetingSticker` | `Bool` | `false` | Код потребителя подключён |
| `hideKeyboardOnScroll` | `Bool` | `true` | Код потребителя подключён |
| `addCommaAfterMention` | `Bool` | `true` | Код потребителя подключён (две панели подсказок) |
| `inlineMathResult` | `Bool` | `true` | Только определение |
| `disableMarkdown` | `Bool` | `false` | Код потребителя подключён (парсер; быстрый пункт меню ещё не перенесён) |
| `hideSendAsPeer` | `Bool` | `false` | Код потребителя подключён |
| `removeMessageTail` | `Bool` | `true` | Только определение |
| `replaceEditedWithIcon` | `Bool` | `true` | Код потребителя подключён |
| `showOnlineStatus` | `Bool` | `false` | Только определение |
| `showForwardsCount` | `Bool` | `false` | Только определение |
| `hideShareButton` | `Bool` | `true` | Код потребителя подключён |
| `showResultsBeforeVoting` | `Bool` | `false` | Только определение |
| `showCopyPhotoButton` | `Bool` | `true` | Только определение |
| `showSaveMessageButton` | `Bool` | `false` | Только определение |
| `showRepeatMessageButton` | `Bool` | `false` | Только определение |
| `showClearButton` | `Bool` | `true` | Только определение |
| `showHistoryButton` | `Bool` | `false` | Только определение |
| `showReportButton` | `Bool` | `true` | Только определение |
| `showGenerateButton` | `Bool` | `true` | Только определение |
| `showDetailsButton` | `Bool` | `false` | Только определение |
| `groupMessageMenu` | `Bool` | `true` | Только определение |
| `recognitionLanguage` | `String` | `"none"` | Только определение |
| `postprocessingWithAi` | `Bool` | `false` | Только определение |
| `extendedFramesPerSecond` | `Bool` | `false` | Только определение |
| `cameraStabilization` | `Bool` | `false` | Только определение |
| `cameraMirrorMode` | `Bool` | `true` | Только определение |
| `rememberLastUsedCamera` | `Bool` | `false` | Только определение |
| `startWithWideAngleCamera` | `Bool` | `false` | Только определение |
| `zoomSlider` | `Bool` | `true` | Только определение |
| `staticZoom` | `Bool` | `false` | Только определение |
| `alwaysSendInHD` | `Bool` | `true` | Только определение |
| `hideCameraTile` | `Bool` | `false` | Код потребителя подключён (обычная галерея вложений) |
| `doubleTapSeekDuration` | `Int32` | `1` | Только определение |
| `preferOriginalQuality` | `Bool` | `false` | Только определение |
| `swipeToPip` | `Bool` | `false` | Только определение |
| `unmuteWithVolumeButtons` | `Bool` | `false` | Только определение |
| `pauseOnMinimizeVideo` | `Bool` | `true` | Только определение |
| `pauseOnMinimizeVoice` | `Bool` | `false` | Только определение |
| `pauseOnMinimizeRound` | `Bool` | `false` | Только определение |
| `useGoogleAnalytics` | `Bool` | `false` | Только определение |
| `enableAdBlock` | `Bool` | `true` | Только определение |
| `updateScheduleTimestamp` | `Int64` | `0` | Только определение |
| `sdkUpdateScheduleTimestamp` | `Int64` | `0` | Только определение |
| `targetLang` | `String` | `"app"` | Код потребителя подключён |
| `flashWarmth` | `Float` | `0.5` | Только определение |
| `flashIntensity` | `Float` | `1.0` | Только определение |
| `pluginsDevMode` | `Bool` | `false` | Неактивно в выбранной Lite |
| `pluginsSafeMode` | `Bool` | `false` | Неактивно в выбранной Lite |
| `pluginsCompactView` | `Bool` | `false` | Неактивно в выбранной Lite |
| `pluginsPySdkAutoUpdate` | `Bool` | `false` | Неактивно в выбранной Lite |
| `pluginsPySdkBetaVersions` | `Bool` | `false` | Неактивно в выбранной Lite |
| `pluginsDisableArtOpts` | `Bool` | `false` | Неактивно в выбранной Lite |
| `pluginsUnknownSources` | `Bool` | `false` | Неактивно в выбранной Lite |
| `pinnedPlugins` | `Set<String>` | `[]` | Неактивно в выбранной Lite |
| `useSystemIconShape` | `Bool` | `true` | Только определение |
| `iconPack` | `ExteraIconPackType` | `.default` | Только определение |
| `dividerStyle` | `ExteraDividerStyle` | `.line` | Только определение |
| `tabIcons` | `ExteraTabIconsMode` | `.titlesOnly` | Только определение |
| `tabCounterMode` | `ExteraTabCounterMode` | `.all` | Только определение |
| `transitionAnimation` | `ExteraTransitionAnimation` | `.spring` | Только определение |
| `glassOutlineStyle` | `ExteraGlassOutlineStyle` | `.glare` | Только определение |
| `stickerTimeMode` | `ExteraStickerTimeMode` | `.default` | Только определение |
| `doubleTapAction` | `Int32` | `1` | Только определение |
| `doubleTapActionOutOwner` | `Int32` | `1` | Только определение |
| `cameraType` | `ExteraCameraType` | `performanceClass == 2 ? CAMERA_X : CAMERA_1; iOS backend не подключён` | Только определение |
| `videoMessagesCamera` | `ExteraVideoMessagesCamera` | `.front` | Только определение |
| `useGoogleCrashlytics` | `Bool` | `false` | Только определение |
