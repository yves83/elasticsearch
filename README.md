
:::info
es_admin is an extendable Elastic Search Administration Script. We can extend the functions by adding the YAML files in action folder.
es_dump is an script to export the Elastic Search index to an JSON file. It can be used for archive the logs.
:::

**The action files contains these fields:**

**name** - The disply name of this action. The file name should align with this name.

**description** - The description message of this action file.

**parameters** - This section defined the paramters required by this action. If there is no paramter, add {} in this field.

**query** - This section defined the HTTP action and HTTP body. The script will replace the ###PLACE_HOLDER### with the parameter values.
