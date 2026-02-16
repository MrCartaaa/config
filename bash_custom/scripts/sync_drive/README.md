# Sync Drive Scripts

This directory contains scripts for syncing files between local workspace and ProtonDrive, with support for client-specific filtering and archiving.

## General Usage

The `sync-drive` command is a dispatcher that routes to pull, push, or teardown operations:

```bash
# Pull files from ProtonDrive to local workspace
sync-drive -p -- [pull options]
sync-drive --pull -- [pull options]

# Push local changes back to ProtonDrive (sync only)
sync-drive -u -- [push options]
sync-drive --push -- [push options]

# Remove local workspace (requires confirmation)
sync-drive -t
sync-drive --teardown
```

### Important Notes
- The `--` separator is **required** when passing arguments to pull or push operations
- Your workspace (`~/ProtonDrive`) must be empty before starting a new pull session
- Use push to sync changes back to ProtonDrive
- Use teardown only when you want to remove the local workspace (requires TTY and confirmation)

### Typical Workflow
```bash
# 1. Start a session by pulling files
sync-drive -p -- -c ugb

# 2. Work on files locally...

# 3. Push changes back (can be done multiple times)
sync-drive -u

# 4. When completely done, teardown the workspace
sync-drive -t
# This will prompt to push changes first (default: Yes)
# Then prompt to confirm teardown (default: No)
```

## Pull Operation Details

### Client (-c) and Path (-p) Flags

The pull operation supports two main modes:

#### 1. Client Mode (`-c`)
Use a client abbreviation to sync a predefined client directory:

```bash
sync-drive -p -- -c ugb                    # Pull entire UGB client folder
sync-drive -p -- -c adc -p invoices/       # Pull only invoices subfolder for ADC
```

Available client abbreviations:
- `adc` → armstrong/adc
- `agf` → armstrong/agf
- `jk` → kegel
- `rh` → houghton
- `hvh` → madigan
- `ugb` → pocock/UGB - Underground Bakeshop

#### 2. Direct Path Mode
Specify a full path starting with `steele_company/clients/`:

```bash
sync-drive -p -- -p steele_company/clients/armstrong/adc/
sync-drive -p -- -p steele_company/clients/new_client/documents/
```

### Filter Behavior

By default, when using client mode (`-c`), a filter file is applied if it exists:
- Filter files are located in: `bash_custom/scripts/sync_drive/{client}.filter`
- Filters use rclone's filter syntax to include/exclude specific files and directories

#### Disabling Filters
Use `--no-filter` to sync everything without filtering:

```bash
sync-drive -p -- -c ugb --no-filter        # Pull ALL files for UGB, ignoring filter
```

### Flag Interoperability

| Mode | Command Example | Behavior |
|------|-----------------|----------|
| Client only | `-c ugb` | Syncs client folder using filter if available |
| Client + subpath | `-c ugb -p invoices/` | Syncs only the invoices subfolder within client, still using filter |
| Client + no filter | `-c ugb --no-filter` | Syncs entire client folder, ignoring filter file |
| Direct path | `-p steele_company/clients/xyz/` | Syncs exact path, no filter applied |
| Direct path + client | Not supported | Error - use one mode or the other |

### Dry Run Mode
Test what would be synced without actually transferring files:

```bash
sync-drive -p -- -c ugb --dry-run
sync-drive -p -- -c ugb -p docs/ --dry-run --no-filter
```

## Push Operation

Push syncs your local changes back to ProtonDrive without removing the workspace:

```bash
sync-drive -u                               # Normal push
sync-drive -u -- --dry-run                  # Preview what would be synced
```

Push features:
- Uses `--delete-during` to remove files from remote that were deleted locally
- Archives replaced/deleted files to `steele_company/_archive/{client}/`
- Preserves the filter settings from your pull session
- Keeps the local workspace intact for continued work

## Teardown Operation

Teardown removes the local workspace after confirming:

```bash
sync-drive -t                               # Remove local workspace
```

Teardown flow:
1. Requires an interactive terminal (TTY)
2. Shows current session information
3. Asks if you want to push changes first:
   - **Y (default)** - Runs push to sync changes before teardown
   - **n** - Skips push and proceeds to teardown confirmation
   - **c** - Cancels the entire operation
4. Asks for final teardown confirmation:
   - **y** - Removes the workspace
   - **N (default)** - Cancels teardown

Note: The safest path (just pressing Enter twice) will push your changes and then cancel the teardown.

## Adding New Clients

To add a new client (e.g., ABC Company):

### 1. Choose an abbreviation
Pick a short, memorable abbreviation (2-3 letters):
```
abc -> ABC Company
```

### 2. Update pull_drive.sh
Edit `/home/jaime/.config/bash_custom/scripts/sync_drive/pull_drive.sh` and add your client to:

a. The usage function (around line 27-33):
```bash
Client Abbreviations:
  adc  -> armstrong/adc
  agf  -> armstrong/agf
  jk   -> kegel
  rh   -> houghton
  hvh  -> madigan
  ugb  -> pocock/UGB - Underground Bakeshop
  abc  -> ABC Company              # Add this line
```

b. The client mapping case statement (around line 77-88):
```bash
case "$CLIENT" in
  adc) CLIENT_PATH="armstrong/adc" ;;
  agf) CLIENT_PATH="armstrong/agf" ;;
  jk)  CLIENT_PATH="kegel" ;;
  rh)  CLIENT_PATH="houghton" ;;
  hvh) CLIENT_PATH="madigan" ;;
  ugb) CLIENT_PATH="pocock/UGB - Underground Bakeshop" ;;
  abc) CLIENT_PATH="ABC Company" ;;     # Add this line
  *)
    log_exit_bad "Invalid client abbreviation: $CLIENT"
    ;;
esac
```

### 3. Create directory structure in ProtonDrive
Ensure the directory exists:
```
ProtonDrive:steele_company/clients/ABC Company/
```

### 4. (Optional) Create a filter file
If you want to exclude certain files/folders, create:
```
/home/jaime/.config/bash_custom/scripts/sync_drive/abc.filter
```

Example filter file content:
```
# Include all files by default
+ **

# Exclude temporary and system files
- .DS_Store
- Thumbs.db
- ~$*
- *.tmp
- *.cache

# Exclude specific directories
- node_modules/**
- .git/**
- build/**
```

### 5. Test the new client
```bash
sync-drive -p -- -c abc --dry-run          # Test pull with filter
sync-drive -p -- -c abc --no-filter --dry-run  # Test pull without filter
```

## Troubleshooting

### "Workspace not clean" error
The workspace directory has files in it. Run teardown first:
```bash
sync-drive -t
```

### "Authentication failure detected"
Re-authenticate with ProtonDrive:
```bash
rclone config reconnect ProtonDrive:
```

### "Missing filter file" error
Either create the filter file or use `--no-filter`:
```bash
sync-drive -p -- -c abc --no-filter
```

### Check active session
The session file stores your current sync state:
```bash
cat ~/ProtonDrive/.session
```