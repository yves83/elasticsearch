
:::info
**es_admin** is an extensible Elasticsearch administration script. Its functionality can be expanded by adding YAML files to the `action` folder.

**es_dump** is a script that exports Elasticsearch indices to JSON files. It can be used to archive logs.

**AzArchive** is a script that extracts Elasticsearch snapshot files and compresses them into a ZIP archive. It is also responsible for uploading and downloading the ZIP file to and from Azure Blob Storage, as well as creating and restoring Elasticsearch snapshots and transferring them to Azure Blob Storage.
:::

**The action files contains these fields:**

**name** - The disply name of this action. The file name should align with this name.

**description** - The description message of this action file.

**parameters** - This section defined the paramters required by this action. If there is no paramter, add {} in this field.

**query** - This section defined the HTTP action and HTTP body. The script will replace the ###PLACE_HOLDER### with the parameter values.
