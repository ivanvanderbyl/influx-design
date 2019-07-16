# Design Goals

We want to achieve superior analytics of time series data with the following characteristics.

## Aggregation on read

We want to minimize aggregation on write, and maximise aggregation on read. In practice, aggregation on read will occur in InfluxDB during queries with InfluxQL and/or Flux.

The client (Flow) should not be expected to aggregate time series data. This will minimise round trips / data sent over the wire make most use of InfluxDB.

## Aggregation on write

It is not practical to write raw point data to InfluxDB due to high write volumes and rates from the tools, hence we need to compromise with some aggregation on write.

Initial aggregation will occur on Grid Nodes using Kapacitor. Further aggregation will occur on InfluxDB, as part of processing (Drain and Pipe) and continuous queries in order to maximise efficiency of write throughput and data management.

## Aggregations

We will provide the following aggregations:

- [mean](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/aggregates/mean/)
- [standard deviation](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/aggregates/stddev/)
- [min](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/selectors/min/)
- [max](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/selectors/max/)
- [count](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/aggregates/count/)
- [sum](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/aggregates/sum/)
- [histograms](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/histogram/)
- [quantiles](https://docs.influxdata.com/flux/v0.24/functions/built-in/transformations/aggregates/quantile/) (p90, p95 and p99)

Aggregations such as min, max, count and sum should 100% accurate. Examples include:

- **min** response time = 2,051 ms
- **max** concurrency = 1,000 users
- **count** passed = 4,069 transactions
- **sum** network = 492,092 bytes received

Aggregations such as the **mean** will include standard error (standard deviation of its sampling distribution), and further aggregations of the same measurements will decrease accuracy and precision of results.

To mitigate this, we will:

-  write **stddev** with the mean
-  write higher precision resolution (1s) for recent floods

Examples include:

- **mean** response time = 2,324 ms over 1s period
- **stddev** response time = 2,324 ms over 1s period

Aggregations such as **histograms** will approximate the cumulative distribution of a data set by counting data frequencies for a list of bins.

Aggregations such as **quantiles** will write records with values that fall within a specified quantile (e.g. 0.95) using the `estimate_tdigest` to output non-null values that fall within the specified quantile.

## Minimise responsibility of the tool

We want to minimise responsibility of the tool plugins (e.g. JMeter) in terms of aggregation (and tagging) so that it emits the minimum amount of data needed to be consumed by Kapacitor.

The tool will emit measurements such as response time, concurrency, passed, failed and objects (traces). Measurements will be emitted at the test step level, with the exception of concurrency, which is emitted at the test case level.

The tool should not be concerned with other tags or fields related to operation of the Grid Node itself. This will be the responsibility of the Grid Node (Kapacitor).

### Provide alternative ways to emit data

We want to provide alternative ways for the tool to emit data, aside from the current UDP streams. This will make it easier for future tools to be integrated with Grid Nodes. For example, uploading a result file or reading from a file descriptor / stream (stdin, stdout).

## Defined series

Series are the collection of data in InfluxDB that share a measurement, tag set, and retention policy. Series names will indicate what type of aggregation has already been applied at write as a _suffix.

### Naming conventions

Series naming conventions should indicate:

- source of the original measurement
- unit of measurement
- aggregation type which has been applied
- any significant groupings by tags which has been applied to the aggregation

`<measurementSource>_<unitOfMeasurement>_<aggregationType>_<totalOrByTag>`

```
concurrent_users_sum_byGrid
throughput_bytes_perSecond_total
passedFailed_requests_perSecond_total
passed_requests_perSecond_byLabel
failed_requests_perSecond_byLabel
```

Defined series are as follows:

### Test step originated series

- **responseTime_milliseconds_mean_byLabelAndType**: mean of elapsed time
  - tags:
    - label_id: _string_ sequential label ID of step
    - type: _string_ step, [stepWithThinkTime, network, timeToFirstByte, timeToFirstInteractive]
  - fields:
    - value: _float_ time in milliseconds
- **responseTime_milliseconds_max_byLabelAndType**: max of elapsed time
  - tags: as above
  - fields:
    - value: _float_ time in milliseconds
- **passed_requests_count_byLabel**: count of passed
  - tags:
    - label_id: _string_ sequential label ID of step
  - fields:
    - value: _int_ count passed
- **failed_requests_count_byLabel**: count of failed
  - tags:
    - label_id: _string_ sequential label ID of step
  - fields:
    - value: _int_ count failed

## Grid Node originated series

- **throughputReceived_bytes_perSecond_total**: sum of network received bytes (sourced from hydrometer)
  - fields:
    - value: _int_ sum bytes
- **throughputTransmitted_bytes_perSecond_total**: sum of network transmitted bytes (sourced from hydrometer)
  - fields:
    - value: _int_ sum bytes

Grid Nodes (Kapacitor) are responsible for additive tag sets related to operation of the Grid Node itself, appended and grouped for all series. These will include:

  - tags:
    - **account**: _string_ primary ID of account
    - **flood**: _string_ sequential flood ID of account
    - **project**: _string_ sequential project ID of account
    - **node**: _string_ sequential node ID of grid, zero based index
    - **grid**: _string_ sequential grid ID of grid, zero based index
    - **region**: _string_ grid region

## Continuous queries

Series can also be derived from other measurements, to facilitate easier/faster querying or produce transformations useful to the client. These will be executed as continuous queries on InfluxDB:

  - **concurrent_users_sum_byGrid**: max of active users
    - tags:
      - grid: _string_ sequential grid ID
    - fields:
      - value: _int_ max users
  - **passedFailed_requests_perSecond_total**: expressed as rate (requests per second), based on sum of passed and failed transactions
     - fields
       - value: _float_ tps
  - **failed_requests_perSecond_total**: expressed as rate (transactions per second), based on sum of failed transactions
    - fields
      - value: _float_ tps
  - **responseTime_milliseconds_histogram_byLabel**: histogram with linear bins (up to max)
    - tags:
      - label_id: _string_ sequential label ID of step
    - fields:
      - value: _float_ time in milliseconds
  - **responseTime_milliseconds_histogram_total**: histogram with linear bins (up to max)
    - fields:
      - value: _float_ time in milliseconds
  - **responseTime_milliseconds_p90_total**: quantile of response time
    - fields:
      - value: _float_ time in milliseconds
  - **responseTime_milliseconds_p95_total**: quantile of response time
    - fields:
      - value: _float_ time in milliseconds
  - **responseTime_milliseconds_p99_total**: quantile of response time
    - fields:
      - value: _float_ time in milliseconds

## Out of scope series

Out of scope are series / measurements with high dimensionality / cardinality, such as server side monitoring and/or tracing.

Handling of these series will be covered in another design document and most likely include their own database, schema design and data processing / management.

## Series cardinality

Series cardinality are the number of unique database, measurement, tag set, and field key combinations in InfluxDB. Best efforts are made (through normalizing tag sets) to reduce cardinality of series.

We will need to test planned limits / constraints on series cardinality for specific tags (labels).

## Schema Design

InfluxDB schema design will be heavily influenced [recommended schema design and data layout](https://docs.influxdata.com/InfluxDB/v1.7/concepts/schema_and_data_layout)

That is:

1. encode metadata in tags
2. avoid using InfluxQL as identifiers
3. don't have too many series
4. don't encode data in measurement names
5. don't put more than one piece of information in one tag

### Shard Design

In general:

- Shard groups should be twice as long as the longest time range of the most frequent queries
- Shard groups should each contain more than 100,000 points per shard group
- Shard groups should each contain more than 1,000 points per series

## Period, Retention Policy and Shard Groups

A [WindowNode](https://docs.influxdata.com/kapacitor/v1.5/nodes/window_node/#sidebar) covers the time range of the aggregation at the GridNode. Historically we have used a WindowNode with a period of 15s.

A design goal for this epic is to write higher precision data to InfluxDB, for the following reasons:

- Customers expect near real time results for live floods, 15 seconds is perceptibly too long.
- Customers want high precision data for running or recent floods, but can tolerate lower precision data for older floods.

We are aiming for the following period, retention policy and shard group durations:

| Alias | Period | RP Duration | Shard Group Duration |
|-------|-------:|------------:|---------------------:|
| Hot   | 1s     | 4w          | 7d                   |
| Warm  | 15s    | 26w         | 4w                   |
| Cold  | 60s    | 156mo       | 52w                  |

This will store 1s data for 4 weeks, 15s data for 6 months and 60s data for 3 years.

```
CREATE RETENTION POLICY "hot" ON "results" DURATION 4w REPLICATION 1 DEFAULT
CREATE RETENTION POLICY "warm" ON "results" DURATION 24w REPLICATION 1
CREATE RETENTION POLICY "cold" ON "results" DURATION 52w REPLICATION 1

CREATE CONTINUOUS QUERY "cq_rollup_responseTime_15s" ON "results" BEGIN
  SELECT mean("response_time")
  INTO "warm"."warm_results"
  FROM "results"
  GROUP BY time(15s)
END

CREATE CONTINUOUS QUERY "cq_rollup_responseTime_60s" ON "results" BEGIN
  SELECT mean("response_time")
  INTO "cold"."cold_results"
  FROM "results"
  GROUP BY time(60s)
END
```
