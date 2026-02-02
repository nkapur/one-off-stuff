# Emulate Limited Disk Volume

hdiutil create -size 500m -type SPARSEBUNDLE -fs "APFS" -volname DVC_Test_Disk ~/Crusoe/DVC_limit_test
hdiutil attach ~/Crusoe/DVC_Limit_Test.sparsebundle
dvc remote add -d local_limit /Volumes/DVC_Test_Disk/dvc_storage

## Error if Out of Disk
```
nkapur@MBP-Navneet-Kapur models % dvc push
Collecting                                                                                                                                                      |12.0 [00:00, 1.19kentry/s]
ERROR: failed to transfer '968fbdcf7682a3608a32ed407794da31' - [Errno 28] No space left on device: '/Users/nkapur/Crusoe/one-off-stuff/.dvc/cache/files/md5/96/8fbdcf7682a3608a32ed407794da31' -> '/Volumes/DVC_Test_Disk/dvc_storage/files/md5/96/.QxU5o47uB5vni6s4u7IwmQ.tmp'
Pushing
ERROR: failed to push data to the cloud - 2 files failed to upload
```
