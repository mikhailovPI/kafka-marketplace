# 1. Создание файла в контейнере
docker exec hadoop-namenode bash -c "echo '<?xml version=\"1.0\"?><test>Hello HDFS</test>' > /tmp/test.xml"

# 2. Проверка создания файла
docker exec hadoop-namenode cat /tmp/test.xml

# 3. Создание директории /test в HDFS (если не существует)
docker exec hadoop-namenode hdfs dfs -mkdir -p /test

# 4. Копирование файла в HDFS
docker exec hadoop-namenode hdfs dfs -put /tmp/test.xml /test/

# 5. Проверка содержимого HDFS
docker exec hadoop-namenode hdfs dfs -ls /test/
docker exec hadoop-namenode hdfs dfs -cat /test/test.xml