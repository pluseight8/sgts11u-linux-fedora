# Security model

* Проект не требует root и не просит отключать Android SELinux.
* Fedora PRoot — удобный compatibility layer, но не security sandbox. Не
  запускайте в нём недоверенные программы с доступом к shared storage.
* Android private app data не bind-ится намеренно. Shared storage подключается
  только после `termux-setup-storage` и только к `/home/fedora/Android`.
* Android bridge не открывает listener на внешнем интерфейсе. Команды Android
  app allowlisted; arbitrary shell execution через bridge не предусмотрен.
* Не храните access tokens, PAT, IMEI, serial или device dumps в репозитории.
* APK не поставляются и не скачиваются silently installer-ом.
* Android остаётся неизменяемым host-слоем: проект не меняет settings, AppOps,
  package/process state, SystemUI, LMKD, zRAM, kernel или hardware services.
  Fedora Shell может только попросить пользователя выбрать себя как `ROLE_HOME`
  через штатный Android UI; One UI Home не удаляется и не отключается.
* Android memory governor является read-only telemetry/reporting компонентом.
  Все профили Linux Mode оптимизируют только Fedora/PRoot user space; Android
  сам управляет cached-app freezer, reclaim и zRAM.
* Сообщения об уязвимостях отправляйте владельцу репозитория приватным каналом;
  не публикуйте личные diagnostics в issue без redaction.
