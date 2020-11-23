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
  # Special case for https://github.com/elastic/kibana/pull/76730
  # To be removed if/when https://github.com/elastic/beats/issues/21092 is resolved
  metricbeat_doc["kibana_stats"]["os"]["cpuacct"] = legacy_doc["kibana_stats"]["os"]["cpuacct"]
  metricbeat_doc["kibana_stats"]["os"]["cpu"] = legacy_doc["kibana_stats"]["os"]["cpu"]

def handle_special_cases(doc_type, legacy_doc, metricbeat_doc):
    if doc_type == "kibana_settings":
        handle_special_case_kibana_settings(legacy_doc, metricbeat_doc)
    if doc_type == "kibana_stats":
        # Starting in 7.11, we want to stop storing `usage` data within Kibana monitoring documents
        # https://github.com/elastic/kibana/issues/83521
        if "usage" in legacy_doc["kibana_stats"]:
          del legacy_doc["kibana_stats"]["usage"]
        if "usage" in metricbeat_doc["kibana_stats"]:
          del metricbeat_doc["kibana_stats"]["usage"]

        # Lens, Actions, and other usage stats might not report consistently.
        # https://github.com/elastic/kibana/issues/80983
        # https://github.com/elastic/kibana/issues/80986
        # https://github.com/elastic/kibana/issues/81944
        # so, we filter out w/e we don't use (or might change)
        handle_special_case_kibana_stats(legacy_doc, metricbeat_doc)


check_parity(handle_special_cases, allowed_deletions_from_metricbeat_docs_extra=allowed_deletions_from_metricbeat_docs_extra)
