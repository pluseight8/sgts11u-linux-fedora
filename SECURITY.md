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
* Сообщения об уязвимостях отправляйте владельцу репозитория приватным каналом;
  не публикуйте личные diagnostics в issue без redaction.

