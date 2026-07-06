# Overview of `rake`
`rake(aka kumade)` is a script for extracting logs from SAS Viya Monitoring for Kubernetes.

The name of the script, rake, is named after a tool used to collect fallen leaves. You can change the name of the script to kumade, râteau, Rechen, rastrello, pá zi, or whatever you like to make it easier to remember.


## Purpose
`rake` was created to simplify log extraction from SAS Viya Monitoring for Kubernetes.  OpenSearch has a 10,000-record limit for log extraction, making it difficult to retrieve logs before and after an error in a single operation.  `rake` overcomes this 10,000-record limit, extracting logs within a specified time range.

- To assist SAS Viya system administrators in error investigation.
- To extract logs from OpenSearch within a specified range.
- To extract logs in a format importable into Excel.
- To easily identify common errors.

## Features
`rake` offers the following features:

- Extracts more than 10,000 lines of logs from OpenSearch in JSON or CSV format from a Linux terminal.
- Automatically creates a configuration file template on the first run.
- Extracts logs from the last 5 minutes if no arguments are provided.
- Allows specifying date and time using formats like E8601DT32.3, `now`, `now-3h`, etc.
- Extracts only feeds frequently referenced during investigations.
- Outputs logs in JSON or CSV format.
- Adds fields to the output file including day, time, minute, second, and checks for common error patterns.

# Introduction
This section describes the prerequisites, placement, and configuration file for the script.

## Prerequisites
This section lists the required environment and configuration information to run the script.

- Environment
    - SAS Viya
    - SAS Viya Monitoring for Kubernetes
- Commands
    - bash
    - jq
    - curl
- Configuration
    - OpenSearch URL and api path
    - OpenSearch username and password

## Deployment
Place the `rake` script in one of the following paths and set execution permissions using `chmod +x`:

- `$HOME/bin/rake`
- `/usr/local/bin/rake`

## Configuration File Creation and Editing
After placing the script, run `rake` without arguments to create the configuration file.  A template configuration file will be created if one doesn't exist.

- `$HOME/.rake/config.json`

Edit the configuration file to set the OpenSearch username, password, and OpenSearch endpoint.  Modify the `api` value if a 404 Not Found error occurs during script execution.

- endpoint
- api
- user
- passwd

After editing the configuration, running `rake` without arguments will extract logs from the last 5 minutes.  If unable to connect to the server or if the username/password is incorrect, an error message will be displayed.  Correct the values in the configuration file based on the error message.  File permissions will be changed after each script execution to protect the password.

## Error Patterns

Common error patterns are registered in the `"default"."queries"` array of the configuration file.  Pattern matching is performed in the order defined in the `queries` array.

This feature facilitates easier error identification by matching extracted logs against these patterns. Users can add patterns by modifying the configuration file.  Note that characters requiring escaping in JSON format cannot be used in patterns due to formatting constraints.


## Configuration File Example

```json
{
  "default": {
    "endpoint": "https://osd.example.com",
    "api": "api/console/proxy",
    "user": "admin",
    "passwd": "password",
    "queries": [
      "The system has encountered an unhandled Exception",
      "ObjectOptimisticLockingFailureException",
      "ODBC SQL Server Wire Protocol driver",
      "Error creating compute session",
      "Error stopping CAS session",
      "Child terminated by signal",
      "ServerOperationException",
      "OAuth token is expired",
      "Unable to launch node",
      "JobExecutionException",
      "Internal Server Error",
      "Unhandled Exception",
      "SAS/TK is aborting",
      "Java heap space",
      "out of memory",
      "OutOfMemory",
      "Unexpected",
      "SSL error",
      "Exception",
      "Failure",
      "killed",
      "panic",
      "OOM"
    ]
  }
}
```

# Functionality

This describes how to run `rake`, its arguments, and the output file format.

## Example Execution

`rake` is designed to run with default options.

```bash
$ rake
Processing...
Extracted 4582 logs from the range now-5m to now.
Saved the logs in the following file.
-rw-rw-r-- 1 azureuser azureuser 2403970 Nov 15 00:19 /tmp/rake.20241115.001936.json
```

## Example Options

Examples are shown before the option descriptions.

| Command       | Description                     |
|---------------|---------------------------------|
| rake         | Extracts logs from the last 5 minutes. |
| rake -h      | Displays help.                   |
| rake -f now-10m | Extracts logs from the last 10 minutes. |
| rake -f 2024-11-01T12:00:00 -t now-1h | Extracts logs from the specified range. |
| rake -c -o /tmp/foo.csv | Saves logs to `/tmp/foo.csv` in CSV format. |
| rake -f now-1w -m "SAS/TK is aborting" | Extracts logs from the last week containing the specified string. |

## Options

### -f _date/time_
Specifies the start point for log extraction. The default value is now-5m.  Acceptable date/time formats are shown below:

| Format             | Description           |
|----------------------|-----------------------|
| 2024-11-14T13:00:15  | Local date/time       |
| 2024-11-14T04:00:15Z | UTC date/time         |
| now                 | Current time          |
| now-30s             | 30 seconds ago        |
| now-1m              | 1 minute ago          |
| now-1h              | 1 hour ago            |
| now-1d              | 1 day ago             |
| now-1w              | 1 week ago            |
| now-1M              | 1 month ago           |
| now-1y              | 1 year ago            |

### -t _date/time_
Specifies the end point for log extraction. The default value is now. Acceptable formats are the same as the -f option.


### -m _text_
Specifies the text to be included in the .message field as a log extraction condition. This option is useful for capturing specific error messages over a relatively long period. Special characters requiring escaping in JSON format (double quotes, {}, [], |) cannot be specified.

### -o _output_
Specifies the output filename.  The default filename is created under /tmp based on a timestamp.

### -l _limit_
Specifies the maximum number of times to call the OpenSearch API. The default is 100.

### -u _user_
Specifies a value to override the user in config.json.

### -p _password_
Specifies a value to override the passwd in config.json.

### -e _endpoint_
Specifies a value to override the endpoint in config.json.

### -c
Changes the output file format to CSV. The default output format is JSON.

### -d
Enable debug mode.

### -h
Displays usage information.

## Output File
The output file content is sorted in ascending order by timestamp.
The output file format is either JSON or CSV. Both formats can be imported using Excel's "Text or CSV from". The output file items are shown below:

| No. | Column Name           | Description                     |
|-----|------------------------|---------------------------------|
| 1   | _index                 | _index                           |
| 2   | _id                    | _id                              |
| 3   | @timestamp             | _source.@timestamp              |
| 4   | hour                   | Hour of @timestamp              |
| 5   | minute                 | Minute of @timestamp             |
| 6   | second                 | Second of @timestamp             |
| 7   | logsource              | _source.logsource               |
| 8   | level                  | _source.level                   |
| 9   | pod                    | _source.kube.pod                |
| 10  | container              | _source.kube.container           |
| 11  | message                | _source.message                 |
| 12  | username               | _source.properties.username      |
| 13  | launcher_sas_com/username | _source.kube.labels.launcher_sas_com/username |
| 14  | launcher_sas_com/requested-by-client | _source.kube.labels.launcher_sas_com/requested-by-client |
| 15  | check                  | Number of matching patterns in message |
| 16  | pattern                | Pattern from config file matched with message |
| 17  | sort                   | Timestamp sort order             |

# Development Notes
Developer notes are documented here.

## Test Environment

- SAS Viya LTS 2024.03
- SAS Viya Monitoring for Kubernetes 1.2.26
- OpenSearch 2.12.0

## Troubleshooting

### 404 Not Found
If the OpenSearch hostname is correct but the request path doesn't exist, modify the `api` value in `config.json`.
To find the correct values, use OpenSearch Dev Tools and your browser's developer tools (F12) together.
Open Dev Tools and display the browser's developer tools.  Run the following query from the Dev Tools Console:

```
GET viya_logs-*/_search
{
  "query": {
    "match_all": {}
  }
}
```
Select the request from the Network tab of the developer tools.  The `Headers/Request URL:` will show the endpoint and `api` values to specify in `config.json`. Depending on the version of OpenSearch, the Copy as cURL feature may be available at times.

In some environments, the protocol was HTTP instead of HTTPS, and the API path was sometimes dashboards/api/console/proxy instead of api/console/proxy.

## Testing
Normal and error test patterns are stored in test/test.sh. When developers modify the script, they should run the test patterns to check that it is working correctly.