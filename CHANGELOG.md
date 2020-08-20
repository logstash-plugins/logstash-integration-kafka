## 10.5.1
  - [DOC]Replaced plugin_header file with plugin_header-integration file. [#46](https://github.com/logstash-plugins/logstash-integration-kafka/pull/46)
  - [DOC]Update kafka client version across kafka integration docs [#47](https://github.com/logstash-plugins/logstash-integration-kafka/pull/47)
  - [DOC]Replace hard-coded kafka client and doc path version numbers with attributes to simplify doc maintenance [#48](https://github.com/logstash-plugins/logstash-integration-kafka/pull/48)  

## 10.5.0
  - Changed: retry sending messages only for retriable exceptions [#27](https://github.com/logstash-plugins/logstash-integration-kafka/pull/29)

## 10.4.1
  - [DOC] Fixed formatting issues and made minor content edits [#43](https://github.com/logstash-plugins/logstash-integration-kafka/pull/43)

## 10.4.0
 - added the input `isolation_level` to allow fine control of whether to return transactional messages [#44](https://github.com/logstash-plugins/logstash-integration-kafka/pull/44)

## 10.3.0
  - added the input and output `client_dns_lookup` parameter to allow control of how DNS requests are made [#28](https://github.com/logstash-plugins/logstash-integration-kafka/pull/28)

## 10.2.0
  - Changed: config defaults to be aligned with Kafka client defaults [#30](https://github.com/logstash-plugins/logstash-integration-kafka/pull/30)

## 10.1.0
  - updated kafka client (and its dependencies) to version 2.4.1 ([#16](https://github.com/logstash-plugins/logstash-integration-kafka/pull/16))
  - added the input `client_rack` parameter to enable support for follower fetching
  - added the output `partitioner` parameter for tuning partitioning strategy
  - Refactor: normalized error logging a bit - make sure exception type is logged
  - Fix: properly handle empty ssl_endpoint_identification_algorithm [#8](https://github.com/logstash-plugins/logstash-integration-kafka/pull/8)
  - Refactor : made `partition_assignment_strategy` option easier to configure by accepting simple values from an enumerated set instead of requiring lengthy class paths ([#25](https://github.com/logstash-plugins/logstash-integration-kafka/pull/25))

## 10.0.1
  - Fix links in changelog pointing to stand-alone plugin changelogs.
  - Refactor: scope java_import to plugin class


## 10.0.0
  - Initial release of the Kafka Integration Plugin, which combines
    previously-separate Kafka plugins and shared dependencies into a single
    codebase; independent changelogs for previous versions can be found:
     - [Kafka Input Plugin @9.1.0](https://github.com/logstash-plugins/logstash-input-kafka/blob/v9.1.0/CHANGELOG.md)
     - [Kafka Output Plugin @8.1.0](https://github.com/logstash-plugins/logstash-output-kafka/blob/v8.1.0/CHANGELOG.md)
