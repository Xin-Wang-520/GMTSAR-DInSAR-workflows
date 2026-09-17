# Existing amp1/amp2 geocoding and change mapping

Upload `run_amp_geocode_change_LT1.sh` to the processing-project root:

```text
/data2/xinw/landsides/nepal_landsides/lutan/ASC/
```

Make it executable:

```bash
chmod +x run_amp_geocode_change_LT1.sh
```

Preview automatic recognition:

```bash
./run_amp_geocode_change_LT1.sh
```

Run formally:

```bash
./run_amp_geocode_change_LT1.sh 1
```

For the current project, the script should recognize:

```text
intf_all/2026182_2026238/
amp1 -> LT1_20260702.PRM -> pre-event
amp2 -> LT1_20260827.PRM -> post-event
```

Results are written beneath:

```text
amplitude_results/2026182_2026238/grd/
amplitude_results/2026182_2026238/png/
```

The PNG directory contains the three individual maps plus
`comparison_pre_post_change_1x3.png`, a one-row/three-column figure with
pre-event power, post-event power, and post/pre dB change.

The existing interferogram directory and its `amp1.grd`, `amp2.grd`, and
`trans.dat` are read only and are not modified.
