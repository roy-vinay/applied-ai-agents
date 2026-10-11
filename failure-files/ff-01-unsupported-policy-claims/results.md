500 trials: 354 planted mistakes, 146 correct answers

| Guard (each layer adds to the one above) | Failures caught | Good answers wrongly blocked |
| --- | ---: | ---: |
| No guards | 0/354 (0%) | 0/146 (0%) |
| + Citation required | 90/354 (25%) | 0/146 (0%) |
| + Citation must exist | 137/354 (39%) | 0/146 (0%) |
| + Citation must match the question | 175/354 (49%) | 10/146 (7%) |
| + Every number must appear in the cited policy (exact text) | 280/354 (79%) | 41/146 (28%) |
| + Same check, with units normalized (24 hours = a day) | 280/354 (79%) | 10/146 (7%) |

Final layer: 79.1% of planted mistakes caught, 6.8% of good answers wrongly blocked.

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
