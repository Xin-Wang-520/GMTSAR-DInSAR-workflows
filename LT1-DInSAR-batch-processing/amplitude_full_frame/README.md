# LT-1 full-frame amplitude-change workflow

This directory is independent of the cropped DInSAR workflow. It reads the
complete products in `../raw/`, aligns the later acquisition to the earlier
acquisition, and makes matched single-scene power/amplitude grids.

It never runs `cut_slc` and never edits files under `../raw/`.

## Run

Preview full-frame alignment:

```bash
./run1_align_full_frame_LT1.sh
```

If the actual processing data are in another directory:

```bash
./run1_align_full_frame_LT1.sh --project /path/to/directory-containing-data.list-and-raw
./run1_align_full_frame_LT1.sh 1 --project /path/to/directory-containing-data.list-and-raw
```

Run full-frame alignment:

```bash
./run1_align_full_frame_LT1.sh 1
```

Preview intensity generation:

```bash
./run2_make_intensity_change_LT1.sh
```

Generate the grids:

```bash
./run2_make_intensity_change_LT1.sh 1
```

## Outputs

`SLC_full/` contains a copied master PRM, links to the original full-frame
SLC/LED files, and a new full-frame SLC resampled onto the master grid.

The intensity script reads `PRF` and `rng_samp_rate` from the master PRM and
uses the same initial-filter choice as GMTSAR `filter.csh` (`gauss15x5`,
`gauss5x5`, or `gauss15x3`). Both dates use that same selected kernel with
`conv 1 1`. It retains those initial-only products and then applies a generated
`gauss_60` kernel to make a second, more strongly smoothed set for comparison.

`products/` contains:

- `*_initial.grd`: power, amplitude and post/pre change after only the
  PRM-selected initial filter.
- `*_60m.grd`: the corresponding products after an additional 60 m Gaussian
  filter.
- `power_*_db.grd`: log-power versions retained for common-scale display.
- `gauss_60` and `ijdec_60.txt`: the generated second-stage filter and its
  sampling report.
- `plots/*.png`: pre-event power, post-event power and post/pre change for both
  filtering levels. Change plots use a common -10 to +10 dB display scale; the
  underlying grids are not clipped.

These are relative, uncalibrated GMTSAR power products in radar coordinates.
They are suitable for same-mode change inspection, but should not be described
as calibrated sigma0/gamma0 without applying the LT-1 calibration metadata.
