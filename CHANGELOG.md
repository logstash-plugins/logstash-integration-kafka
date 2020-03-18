## 10.1.0
  - updated kafka client (and its dependencies) to version 2.4.1
  - added the input `client_rack` parameter to enable support for follower fetching
  - added the output `partitioner` parameter for tuning partitioning strategy
  - Refactor: normalized error logging a bit - make sure exception type is logged

## 10.0.1
  - Fix links in changelog pointing to stand-alone plugin changelogs.
  - Refactor: scope java_import to plugin class


## 10.0.0
  - Initial release of the Kafka Integration Plugin, which combines
    previously-separate Kafka plugins and shared dependencies into a single
    codebase; independent changelogs for previous versions can be found:
     - [Kafka Input Plugin @9.1.0](https://github.com/logstash-plugins/logstash-input-kafka/blob/v9.1.0/CHANGELOG.md)
     - [Kafka Output Plugin @8.1.0](https://github.com/logstash-plugins/logstash-output-kafka/blob/v8.1.0/CHANGELOG.md)
