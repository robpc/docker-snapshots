# docker-snapshots

Maintains a rolling set of snapshots for files shared with this container.

## Options

These are the options that can be changed by environment variables (defaults indicated where appropriate).

    SNAPSHOT_NAME=snapshot
    SNAPSHOT_TIMESTAMP_FORMAT=%Y%m%d-%H%M%S
    SNAPSHOT_INTERVAL=         # Seconds. No value runs through the snapshoting once
    SNAPSHOT_MAX_NUM=5
    SNAPSHOT_LOCATION=         # No default. Example: /data/logs
    SNAPSHOT_DESTINATION=      # No default. Example: /data/backup or s3://backup
    SNAPSHOT_METHOD=           # No default. Options: local | s3
    SNAPSHOT_COMPRESSION=tar   # Options: tar | zip
    DEBUG=false