# Reproducing the literature search

This folder contains everything needed to re-run and verify the scoped
systematic literature review reported in Section 3.2, Figure 1 and Table 2 of
the paper.

## Provenance

The search was executed on **6 September 2026**
against the OpenAlex REST API. The scripts here are uploaded
afterwards in order to reproduce the experiment with the same six search strings,
the same endpoint, the same filters, the same deduplication rule.
The CSVs are the primary evidence.

## Why OpenAlex rather than Scopus or IEEE Xplore

Scopus and Web of Science require institutional subscriptions. IEEE Xplore, the
ACM Digital Library, ScienceDirect, SpringerLink and Google Scholar block
automated querying. OpenAlex aggregates records from those publishers and exposes
a public API, so this search can be replicated without institutional access. This
choice is stated in the paper and recorded in Appendix A.

## Scripts

| Script | Purpose | Network |
|---|---|---|
| `01_run_search.ps1` | Runs the six protocol strings, writes `searchlog_raw.csv` and `searchlog_dedup.csv` | Yes |
| `02_compute_prisma.ps1` | Recomputes every number in Figure 1 from the committed CSVs and checks them against the paper | No |
| `03_sensitivity_analysis.ps1` | Reproduces Table 2: how many known studies each string set retrieves | Yes (use `-SkipLiveQueries` for the offline half) |

Run from the repository root:

```powershell
.\scripts\01_run_search.ps1          # regenerates the search logs (overwrites CSVs)
.\scripts\02_compute_prisma.ps1      # verifies Figure 1; exits non-zero on mismatch
.\scripts\03_sensitivity_analysis.ps1
.\scripts\03_sensitivity_analysis.ps1 -SkipLiveQueries
```

Requires Windows PowerShell 5.1 or PowerShell 7+. No modules or API key needed.

## Expected output

`02_compute_prisma.ps1` should reproduce Figure 1 exactly and print
`All figures reconcile.`:

```
Records identified by database search            233
  duplicate OpenAlex identifiers removed           4
  duplicate titles removed (code E6)              35
Records screened on title                        194
Records excluded at screening                     37
Records retained after title screening           157
```

`03_sensitivity_analysis.ps1 -SkipLiveQueries` should report a quasi-gold
standard of 34 AI-focused studies, of which the protocol strings retrieve 2.

## Data files

| File | Rows | Contents |
|---|---|---|
| `searchlog_raw.csv` | 233 | Every record returned, tagged with the string that found it |
| `searchlog_dedup.csv` | 229 | After removing duplicate OpenAlex identifiers |
| `screening_batch1.csv` | 77 | Title-level screening decisions |
| `screening_batch2.csv` | 76 | Title-level screening decisions |
| `screening_batch3.csv` | 76 | Title-level screening decisions |

Screening columns: `id`, `decision` (`INCLUDE`/`EXCLUDE`), `reason`.

Exclusion reason codes:

| Code | Meaning |
|---|---|
| `E1` | Not about AI, machine learning or data-driven methods |
| `E2` | AI/ML study with no software-project or project-management link |
| `E3` | Project-management study in a clearly non-IT domain |
| `E4` | Not a research contribution (editorial, front matter, erratum) |
| `E5` | Not in English |
| `E6` | Duplicate title of another record — a second deduplication stage |

## Two honest limitations

**Screening is not reproducible by script.** Title-level screening was a
judgement task against the criteria in Appendix A. `02_compute_prisma.ps1` only
aggregates the decisions; it cannot regenerate them. The decisions are recorded
per record so that a reader can disagree with any individual one.

**Counts drift.** OpenAlex is continuously updated, so re-running
`01_run_search.ps1` will not necessarily return 233 records. The committed CSVs
are the 6 September 2026 snapshot on which the paper's figures are based. Record
the date of any re-run.

## Known pitfall

Some OpenAlex responses contain JSON keys differing only in case (for example
`To` and `to`), which makes PowerShell 5.1's `ConvertFrom-Json` throw and
silently return no count. The scripts therefore read result counts by regex from
the raw response body, and request only the fields they need via the `select`
parameter. If you rewrite these scripts in another language, this is the trap to
watch for.
