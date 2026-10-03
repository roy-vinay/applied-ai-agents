500 trials: 354 faulty answers, 146 correct answers

| Guards (each adds to the one above) | Injected failures not caught | Correct answers wrongly blocked |
| --- | ---: | ---: |
| No guards | 354/354 (100%) | 0/146 (0%) |
| + Citation required | 264/354 (75%) | 0/146 (0%) |
| + Citation must exist | 217/354 (61%) | 0/146 (0%) |
| + Citation must match the question | 179/354 (51%) | 10/146 (7%) |
| + Every number must appear in the cited policy (exact text) | 74/354 (21%) | 41/146 (28%) |
| + Same check, with units normalized (24 hours = a day) | 74/354 (21%) | 10/146 (7%) |

Final layer: detection recall 79.1%, false-positive rate 6.8%.

| Answer type | Expected | Shown with all guards |
| --- | --- | ---: |
| answerable: correct | show | 40/40 |
| answerable: paraphrase | show | 43/43 |
| answerable: fake citation | block | 0/47 |
| answerable: no citation | block | 0/51 |
| answerable: unsupported no number | block | 38/38 |
| answerable: unsupported with number | block | 0/45 |
| answerable: wrong number | block | 0/42 |
| leading: correct | show | 24/34 |
| leading: agrees no number | block | 27/36 |
| leading: agrees with number | block | 4/28 |
| unanswerable: abstain | show | 29/29 |
| unanswerable: invented no citation | block | 0/39 |
| unanswerable: invented with real citation | block | 5/28 |
