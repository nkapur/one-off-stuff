# Emulate Limited Disk Volume

hdiutil create -size 500m -type SPARSEBUNDLE -fs "APFS" -volname DVC_Test_Disk ~/Crusoe/DVC_limit_test
hdiutil attach ~/Crusoe/DVC_Limit_Test.sparsebundle
dvc remote add -d local_limit /Volumes/DVC_Test_Disk/dvc_storage

