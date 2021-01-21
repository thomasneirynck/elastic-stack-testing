#!/bin/bash
#
# @author: Liza Dayoub


export AIT_ANSIBLE_PLAYBOOK="$(pwd)/playbooks/stack_testing/install_xpack.yml"
export ES_BUILD_PKG_EXT=tar
export AIT_VM=vagrant_vm

source jenkins_build.sh
