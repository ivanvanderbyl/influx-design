# Design Goals

<!-- @import "[TOC]" {cmd="toc" depthFrom=1 depthTo=6 orderedList=false} -->

We want to achieve superior analytics of time series data with the following characteristics.

## Aggregation on read

We want to minimize aggregation on write, and maximise aggregation on read where practical. In practice, aggregation on read will occur in InfluxDB during queries with InfluxQL and/or Flux.

The client (Flow) should not be expected to aggregate time series data. This will minimise data round trips / data sent over the wire and maximise the functionality of InfluxDB itself.

## Aggregation on write

It is not practical to write raw point data to InfluxDB due to high write volumes and rates from the tools themselves, hence we need to accept a minimum form of aggregation on write.

Aggregation occurs on Grid Nodes via Kapacitor, as part of their current UDP stream processing (tool emits data to Kapacitor via UDP).

Further aggregation will occur on InfluxDB, as part of pipe line processing (Drain, Pipe) and continuous queries in order to maximise efficiency of write throughput, retention policy and shard management.

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

- min response time = 2,051 ms
- max concurrency = 1,000 users
- count passed = 4,069 transactions
- sum network = 492,092 bytes received

These aggregations will occur on Grid Nodes via Kapacitor and be accurately written into InfluxDB.

Aggregations such as the mean will include standard error (standard deviation of its sampling distribution), and further aggregations of the same measurements will decrease accuracy and precision of results.

To assist with this, we will write higher precision aggregates for new data (e.g. 1s resolution for last 30 days) and move to lower precision aggregates for older data (e.g.15s resolution greater than 12 months). For aggregates such as mean we will also write standard deviation. Examples include:

- mean response time = 2,324 ms over 1s period
- stddev response time = 2,324 ms over 1s period

Aggregations such as histograms will approximate the cumulative distribution of a data set by counting data frequencies for a list of bins.

Aggregations such as quantiles will write records from an input table with _values that fall within a specified quantile (e.g. 0.95) using the `estimate_tdigest` to output non-null records with values that fall within the specified quantile.

## Minimise responsibility of the tool

We want to minimise the responsibility of tool e.g. JMeter in terms of aggregation and labelling so that it emits the minimum amount of data needed to be consumed by Flood.

Ideally the tool should emit 'common' measurements such as response time, concurrency, passed, failed and traces. Measurements are typically emitted at the test step level, with the exception of concurrency, which is emitted at the test case level.

The tool should not be concerned with other tag sets related to operation of the tool itself. This is the responsibility of the aggregation point, typically the grid node.

### Provide alternative ways to emit data

We want to provide alternative options for the tool to emit data, aside from the current UDP streams, to increase the options available to customers for emitting data. For example, uploading a test result as a file or the ability read a file descriptor streams (stdin, stdout, stderr).

## Defined series

Measurements are produced by the tool (JMeter, Gatling, Element etc), aggregated by the node (Kapacitor) and then written via a pipe line (Drain, Pipe) to the time series database (InfluxDB).

Measurements are scoped to the individual test step / transaction level, and also at the test case level for any grid node. Series are the collection of data in the InfluxDB that share a measurement, tag set, and retention policy.

Series cardinality are the number of unique database, measurement, tag set, and field key combinations in InfluxDB.

Defined series are as follows:

### Test step series

- **response_time**: mean of elapsed time
  - tags:
    - label_id: _string_ sequential label ID of step
    - type: _string_ step,stepWithThinkTime, network, timeToFirstInteractive, timeToFirstByte
  - fields:
    - value: _float_ time in milliseconds
- **passed**: count of passed
  - tags:
    - label_id: _string_ sequential label ID of step
  - fields:
    - value: _int_ total count
- **failed**: count of failed
  - tags:
    - label_id: _string_ sequential label ID of step
  - fields:
    - value: _int_ total count

### Test case series

- **concurrency**: count of active users
  - fields:
    - value: _int_ total count

## Grid node series

- **network_rx**: sum of network received bytes
  - fields:
    - value: _int_ total bytes
- **network_tx**: sum of network transmitted bytes
  - fields:
    - value: _int_ total bytes

Grid nodes (Kapacitor) is responsible for additive tag sets related to operation of the tool itself. These will include:

  - tags:
    - **account**: _string_ primary ID of account
    - **flood**: _string_ sequential flood ID of account
    - **project**: _string_ sequential project ID of account
    - **node**: _string_ sequential node ID of grid, zero based index
    - **grid**: _string_ sequential grid ID of grid, zero based index
    - **region**: _string_ grid region

## Derived series

Series can also be derived from tool / grid produced measurements, to facilitate easier/faster querying or produce transformations useful to the UI. These will be executed as continuous queries on InfluxDB

  - **transaction_rate**: non negative derivative expressed as transactions per second, based on sum of passed and failed transactions
     - fields
       - value: _float_
  - **error_rate**: non negative derivative expressed as transactions per second, based on sum of failed transactions
    - fields
      - value: _float_
 - **network_rx_rate**: non negative derivative of network received, expressed as bits per second
 - **network_tx_rate**: non negative derivative of network transmitted, expressed as bits per second
 - **response_time_histogram**: histogram with linear bins (up to max)
 - **response_time_p90**: quantile of response time
 - **response_time_p95**: quantile of response time
 - **response_time_p99**: quantile of response time

## Out of scope series

Out of scope for this design document, but under consideration, are series / measurements with high dimensionality / cardinality, such as server side monitoring and/or tracing.

Handling of these series will be covered in another design document and most likely include their own schema design and data management.

## Schema Design

InfluxDB. schema design will be heavily influenced [recommended schema design and data layout](https://docs.influxdata.com/InfluxDB/v1.7/concepts/schema_and_data_layout)

That is:

1. encode metadata in tags
2. avoid using InfluxQL as identifiers
3. don't have too many series
4. don't encode data in measurement names
5. don't put more than one piece of information in one tag

## Precision

A [WindowNode](https://docs.influxdata.com/kapacitor/v1.5/nodes/window_node/#sidebar) covers the time range of the aggregation at the GridNode. Historically we have used a WindowNode with a period of 15s. For the purpose of this document, 15s is considered low precision.

A design goal for this epic is to write higher precision data to InfluxDB, for the following reasons:

- Customers expect near real time results for live floods, 15 seconds is perceptibly long.
- Customers want high precision data for running or recent floods, and can handle lower precision data for older floods.

In general:

- Shard groups should be twice as long as the longest time range of the most frequent queries
- Shard groups should each contain more than 100,000 points per shard group
- Shard groups should each contain more than 1,000 points per series

We are aiming for the following period, reternion policy and shard group durations:

| Alias | Period | RP Duration | Shard Group Duration |
|-------|-------:|------------:|---------------------:|
| Hot   | 1s     | 1mo         | 7d                   |
| Warm  | 15s    | 12mo        | 26w                  |
| Cold  | 30s    | 36mo        | 52w                  |

```
CREATE RETENTION POLICY "hot" ON "results" DURATION 4w REPLICATION 1 DEFAULT
CREATE RETENTION POLICY "warm" ON "results" DURATION 24w REPLICATION 1
CREATE RETENTION POLICY "cold" ON "results" DURATION 52w REPLICATION 1
```
