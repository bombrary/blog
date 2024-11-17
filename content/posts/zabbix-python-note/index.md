---
title: "PythonでZabbixを操作したメモ"
date: 2024-11-17T12:10:19Z
draft: true
tags: []
categories: [ "Zabbix", "Python" ]
---

## やること

* ホストのトリガーを取得する
* ホストのトリガーのenable/disableをまとめて切り替える

## インターフェースの実装

例えばclickでI/Fを実装するとこんな感じ。

```python
logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
handler = logging.StreamHandler(sys.stderr)
handler.setLevel(logging.DEBUG)
logger.addHandler(handler)

@click.group()
def cli():
    pass

def parse_status_num(status_num: int) -> Literal["enabled", "disabled", "UNKNOWN"]:
    match status_num:
        case "0":
            return "enabled"
        case "1":
            return "disabled"
        case _:
            return "UNKNOWN"

HELP_SET_TRIGGER_STATUS_CLI = """
ホストのトリガーのステータスを変更する
"""

@cli.command("set-trigger-status", help=HELP_SET_TRIGGER_STATUS_CLI)
@click.option("--zabbix-url", "zabbix_url", envvar="ZABBIX_SERVER_URL", required=True, show_envvar=True, help="Zabbix ServerのURL")
@click.option("--zabbix-user", "zabbix_user", envvar="ZABBIX_SERVER_USER", required=True, show_envvar=True, help="Zabbix Serverのユーザ名")
@click.option("--zabbix-pass", "zabbix_pass", envvar="ZABBIX_SERVER_PASS", required=True, show_envvar=True, help="Zabbix Serverのパスワード")
@click.option("--host", "host_name", required=True, help="host名")
@click.option("--status", "trigger_status", type=click.Choice(["enabled", "disabled"]), required=True, help="変更後のtriggerのstatus")
@click.option("--apply", "apply_flag", required=False, is_flag=True, help="変更を反映する")
def set_trigger_status_cli(
    zabbix_url: str,
    zabbix_user: str,
    zabbix_pass: str,
    host_name: str,
    trigger_status: Literal["enabled", "disabled"],
    apply_flag: bool,
):
    client = ZabbixHandler(zabbix_url, zabbix_user, zabbix_pass, apply_flag)

    trigger_descriptions = [ "trigger A", "trigger B" ]
    triggers = client.list_triggers_by_host(host_name, trigger_descriptions)
    triggers_to_be_changed = []

    for trigger in triggers:
        status_text = parse_status_num(trigger["status"])
        logger.info({ "trigger": {
            "triggerid": trigger["triggerid"] ,
            "description": trigger["description"],
            "status_raw": f"{trigger['status']}",
            "status": status_text,
        }})
        if status_text != trigger_status:
            triggers_to_be_changed.append(trigger)

    for trigger in triggers_to_be_changed:
        client.set_trigger_status(trigger, trigger_status)

    logger.info({
        "triggers": len(triggers),
        "triggers_to_be_changed": len(triggers_to_be_changed)
    })
```

## requestsを用いたインターフェース内部実装

## pyzabbixを用いたインターフェース内部実装

使用感としては実はrequestsと対して変わらない。jsonrpcが見えなくなっただけで、必要なパラメータは変わらないし、返却値もdictである。

```python
class ZabbixHandler:
    def __init__(self, host: str, user: str, password: str, apply_flag: bool):
        self.zapi = ZabbixAPI(f"http://{host}", user=user, password=password)
        self.apply_flag = apply_flag
        logger.info("Connected to Zabbix API Version %s" % self.zapi.api_version())

    def get_host_by_name(self, name: str) -> dict[str, Any] | None:
        hosts = self.zapi.host.get(
            filter={
                "host": [ name ],
            },
        )
        if len(hosts) == 1:
            return hosts[0]
        else:
            return None

    def list_triggers_by_host(self, host_name: str, descriptions: list[str]) -> list[dict[str, Any]]:
        hosts = [ host_name ]
        if len(descriptions) == 0:
            return []
        else:
            logger.info({ "url": self.zapi.url, "method": "trigger.get", "params": { "host": hosts, "description": descriptions }})
            return self.zapi.trigger.get(
                filter={
                    "host": hosts,
                    "description": descriptions,
                },
            )

    def set_trigger_status(self, trigger: dict[str, Any], status: Literal["enabled", "disabled"]):
        trigger_id = trigger["triggerid"]
        match status:
            case "enabled":
                status_num = 0
            case "disabled":
                status_num = 1
            case _:
                raise ValueError(f"Invalid trigger status: {status}")

        if self.apply_flag:
            logger.info({ "url": self.zapi.url, "method": "trigger.update", "params": { "triggerid": trigger_id, "status": status_num }})
            res = self.zapi.trigger.update(triggerid=trigger_id, status=status_num)
            logger.info(f"response: {res}")
```
