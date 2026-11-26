**es_admin** is an extensible Elasticsearch administration script. Its functionality can be expanded by adding YAML files to the `action` folder.

**es_dump** is a script that exports Elasticsearch indices to JSON files. It can be used to archive logs.

**AzArchive** is a script that extracts Elasticsearch snapshot files and compresses them into a ZIP archive. It is also responsible for uploading and downloading the ZIP file to and from Azure Blob Storage, as well as creating and restoring Elasticsearch snapshots and transferring them to Azure Blob Storage.
