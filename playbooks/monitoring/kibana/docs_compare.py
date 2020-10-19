'''
Usage:
  python docs_compare.py /path/to/legacy/docs /path/to/metricbeat/docs
'''

from docs_compare_util import check_parity
import sys

allowed_deletions_from_metricbeat_docs_extra = [
  # 'path.to.field'
  'kibana_stats.response_times.max',
  'kibana_stats.response_times.average'
]

def handle_special_case_kibana_settings(legacy_doc, metricbeat_doc):
  # Legacy collection will index kibana_settings.xpack.default_admin_email as null
  # whereas Metricbeat collection simply won't index it. So if we find kibana_settings.xpack.default_admin_email 
  # is null, we simply remove it
  if "xpack" in legacy_doc["kibana_settings"] \
    and "default_admin_email" in legacy_doc["kibana_settings"]["xpack"] \
    and legacy_doc["kibana_settings"]["xpack"]["default_admin_email"] == None:
    legacy_doc["kibana_settings"]["xpack"].pop("default_admin_email")

def handle_special_case_kibana_stats(legacy_doc, metricbeat_doc):
  # Special case this until we have resolution on https://github.com/elastic/kibana/pull/70677#issuecomment-662531529
  metricbeat_doc["kibana_stats"]["usage"]["search"]["total"] = legacy_doc["kibana_stats"]["usage"]["search"]["total"]
  metricbeat_doc["kibana_stats"]["usage"]["search"]["averageDuration"] = legacy_doc["kibana_stats"]["usage"]["search"]["averageDuration"]

  # Special case for https://github.com/elastic/kibana/pull/76730
  # To be removed if/when https://github.com/elastic/beats/issues/21092 is resolved
  metricbeat_doc["kibana_stats"]["os"]["cpuacct"] = legacy_doc["kibana_stats"]["os"]["cpuacct"]
  metricbeat_doc["kibana_stats"]["os"]["cpu"] = legacy_doc["kibana_stats"]["os"]["cpu"]

  # Actions usage stats do not report consistently. https://github.com/elastic/kibana/issues/80986
  metricbeat_doc["kibana_stats"]["usage"]["actions"] = legacy_doc["kibana_stats"]["usage"]["actions"]
  metricbeat_doc["kibana_stats"]["usage"]["alerts"] = legacy_doc["kibana_stats"]["usage"]["alerts"]

def handle_special_cases(doc_type, legacy_doc, metricbeat_doc):
    if doc_type == "kibana_settings":
        handle_special_case_kibana_settings(legacy_doc, metricbeat_doc)
    if doc_type == "kibana_stats":
        handle_special_case_kibana_stats(legacy_doc, metricbeat_doc)


check_parity(handle_special_cases, allowed_deletions_from_metricbeat_docs_extra=allowed_deletions_from_metricbeat_docs_extra)
