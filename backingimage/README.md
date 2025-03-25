Check disk in status but not in spec
    $ ./check_backingimage_mismatch.sh

Find BI w/o valid replica and along with the bbi and volume reference to it
    $ ./find_non_full_ready_backingimage.sh

Restore a bi from bbi if possible
    Dryrun:
        $ ./restore_bi_from_backup.sh --dry-run default-image-8jbpn
    Actual run:
        $ ./restore_bi_from_backup.sh default-image-8jbpn