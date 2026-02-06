#!/usr/bin/bash
echo 'running sftp file sync with cloud...\n'

cd "${DRIVE_PATH}"

printf "accessed directory: $(pwd)"
printf "attempting to sync to fz:\n$(ls)"
echo "running 'fzcli' command:"

'/mnt/c/Program Files/FileZilla Pro CLI/fzcli.exe' --mode batch --script .sftp_sync_script.txt

echo "\ncompleted sftp file sync."
