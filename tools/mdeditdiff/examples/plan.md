# Export reports to CSV

Customers want to download any report as a spreadsheet. This plan covers the first version.

## Steps

1. Add an **Export** button to the report page.
2. Build the CSV on the server.
3. Write tests for empty and very large reports.
4. Ship behind the `csv_export` feature flag.

## Open questions

- Should exports include archived rows?
- What is the row limit?

## Rollout

| Stage | Who | When |
| --- | --- | --- |
| Internal | Support team | Week 1 |
| Beta | 10 customers | Week 2 |
| Everyone | All plans | Week 4 |

> Keep the first version simple. Scheduled exports can come later.
