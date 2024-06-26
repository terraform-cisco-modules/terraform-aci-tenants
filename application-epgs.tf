/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "fvAEPg"
 - Distinguished Name: uni/tn-{tenant}/ap-{application_profile}/epg-{application_epg}
GUI Location:
Tenants > {tenant} > Application Profiles > {application_profile} > Application EPGs > {application_epg}
_______________________________________________________________________________________________________________________
*/
resource "aci_application_epg" "map" {
  depends_on = [aci_tenant.map, aci_application_profile.map, aci_bridge_domain.map]
  for_each = {
    for k, v in local.application_epgs : k => v if v.epg_type == "standard" && local.controller.type == "apic"
  }
  application_profile_dn = "uni/tn-${each.value.tenant}/ap-${each.value.application_profile}"
  description            = each.value.description
  exception_tag          = each.value.contract_exception_tag
  flood_on_encap         = each.value.flood_in_encapsulation
  fwd_ctrl               = each.value.intra_epg_isolation == "enforced" ? "proxy-arp" : "none"
  has_mcast_source       = each.value.has_multicast_source == true ? "yes" : "no"
  is_attr_based_epg      = each.value.useg_epg == true ? "yes" : "no"
  match_t                = each.value.label_match_criteria
  name                   = each.value.name
  name_alias             = each.value.alias
  pc_enf_pref            = each.value.intra_epg_isolation
  pref_gr_memb           = each.value.preferred_group_member == true ? "include" : "exclude"
  prio                   = each.value.qos_class
  shutdown               = each.value.epg_admin_state == "admin_shut" ? "yes" : "no"
  relation_fv_rs_bd      = "uni/tn-${each.value.tenant}/BD-${each.value.bridge_domain}"
  relation_fv_rs_sec_inherited = [
    for s in each.value.epg_contract_masters : "uni/tn-${each.value.tenant}/ap-${s.application_profile}/epg-${s.application_epg}"
  ]
  relation_fv_rs_cust_qos_pol = length(compact([each.value.custom_qos_policy])
  ) > 0 ? "uni/tn-${local.policy_tenant}/qoscustom-${each.value.custom_qos_policy}" : ""
  relation_fv_rs_dpp_pol = each.value.data_plane_policer
  relation_fv_rs_aepg_mon_pol = length(compact([each.value.monitoring_policy])
  ) > 0 ? "uni/tn-${local.policy_tenant}/monepg-${each.value.monitoring_policy}" : ""
  relation_fv_rs_trust_ctrl = length(compact([each.value.fhs_trust_control_policy])
  ) > 0 ? "uni/tn-${local.policy_tenant}/trustctrlpol-${each.value.fhs_trust_control_policy}" : ""
}


/*_____________________________________________________________________________________________________________________

* Inband
API Information:
 - Class: "mgmtInB"
 - Distinguished Name: "uni/tn-mgmt/mgmtp-default/inb-{epg}"
GUI Location:
 - Tenants > mgmt > Node Management EPGs > In-Band EPG - {epg}

* Out-of-Band
API Information:
 - Class: "mgmtOoB"
 - Distinguished Name: "uni/tn-mgmt/mgmtp-default/oob-{epg}"
GUI Location:
 - Tenants > mgmt > Node Management EPGs > Out-of-Band EPG - {epg}
_______________________________________________________________________________________________________________________
*/
resource "aci_node_mgmt_epg" "mgmt_epgs" {
  depends_on = [aci_bridge_domain.map]
  for_each = {
    for k, v in local.application_epgs : k => v if length(regexall("(inb|oob)", v.epg_type)
    ) > 0 && local.controller.type == "apic"
  }
  management_profile_dn    = "uni/tn-mgmt/mgmtp-default"
  name                     = each.value.name
  encap                    = each.value.epg_type == "inb" ? "vlan-${element(each.value.vlans, 0)}" : ""
  match_t                  = each.value.epg_type == "inb" ? each.value.label_match_criteria : "AtleastOne"
  name_alias               = each.value.alias
  pref_gr_memb             = "exclude"
  prio                     = each.value.qos_class
  type                     = each.value.epg_type == "inb" ? "in_band" : "out_of_band"
  relation_mgmt_rs_mgmt_bd = each.value.epg_type == "inb" ? "uni/tn-mgmt/BD-${each.value.bridge_domain}" : ""
}


#---------------------------------------------------------
# Configure External Management Network Instance Profiles
#---------------------------------------------------------

/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "mgmtInstP"
 - Distinguished Name: "uni/tn-mgmt/extmgmt-default/instp-{name}"
GUI Location:
 - tenants > mgmt > External Management Network Instance Profiles > {name}
_______________________________________________________________________________________________________________________
*/
resource "aci_rest_managed" "external_management_network_instance_profiles" {
  depends_on = [aci_l3_outside.map]
  for_each   = { for k, v in local.application_epgs : k => v if v.epg_type == "oob" }
  dn         = "uni/tn-mgmt/extmgmt-default/instp-${each.value.name}"
  class_name = "mgmtInstP"
  content = {
    #annotation = "orchestrator:terraform"
    #    name = each.value.name
  }
}


/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "tagAnnotation"
 - Distinguished Name: "uni/tn-{tenant}/ap-{application_profile}/epg-{application_epg}/annotationKey-[{key}]"
GUI Location:
 - Tenants > {tenant} > Application Profiles > {application_profile} > Application EPGs > {application_epg}: {annotations}
_______________________________________________________________________________________________________________________
*/
resource "aci_rest_managed" "application_epgs_annotations" {
  depends_on = [aci_application_epg.map]
  for_each = {
    for i in flatten([
      for a, b in local.application_epgs : [
        for v in b.annotations : {
          application_profile = b.application_profile
          application_epg     = b.name
          key                 = v.key
          tenant              = b.tenant
          value               = v.value
          epg_type            = b.epg_type
        }
      ]
      ]) : "${i.application_profile}:${i.application_epg}:${i.key}" => i if length(regexall("standard", i.epg_type)
    ) > 0 && local.controller.type == "apic"
  }
  dn         = "uni/tn-${each.value.tenant}/ap-${each.value.application_profile}/epg-${each.value.application_epg}/annotationKey-[${each.value.key}]"
  class_name = "tagAnnotation"
  content = {
    key   = each.value.key
    value = each.value.value
  }
}


/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "tagAliasInst"
 - Distinguished Name: "uni/tn-{tenant}/ap-{application_profile}/epg-{application_epg}/alias"
GUI Location:
 - Tenants > {tenant} > Application Profiles > {application_profile} > Application EPGs > {application_epg}: global_alias

_______________________________________________________________________________________________________________________
*/
resource "aci_rest_managed" "application_epgs_global_alias" {
  depends_on = [aci_application_epg.map]
  for_each   = { for k, v in local.application_epgs : k => v if v.global_alias != "" && local.controller.type == "apic" }
  class_name = "tagAliasInst"
  dn         = "uni/tn-${each.value.tenant}/ap-${each.value.application_profile}/epg-${each.value.name}/alias"
  content = {
    name = each.value.global_alias
  }
}


/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "fvRsDomAtt"
 - Distinguished Name: uni/tn-{tenant}/ap-{application_profile}/epg-{application_epg}/rsdomAtt-[uni/{domain}]
GUI Location:
Tenants > {tenant} > Application Profiles > {application_profile} > Application EPGs > {application_epg} > Domains (VMs and Bare-Metals)
_______________________________________________________________________________________________________________________
*/
resource "aci_epg_to_domain" "map" {
  depends_on = [aci_application_epg.map]
  for_each = {
    for k, v in local.epg_to_domains : k => v if local.controller.type == "apic" && v.epg_type == "standard"
  }
  application_epg_dn = aci_application_epg.map[each.value.key].id
  tdn = length(
    regexall("physical", each.value.domain_type)
    ) > 0 ? "uni/phys-${each.value.domain}" : length(
    regexall("vmm", each.value.domain_type)
  ) > 0 ? "uni/vmmp-${each.value.switch_provider}/dom-${each.value.domain}" : ""
  binding_type = length(
    regexall("physical", each.value.domain_type)
    ) > 0 ? "none" : length(regexall(
      "dynamic_binding", each.value.port_binding)) > 0 ? "dynamicBinding" : length(regexall(
      "default", each.value.port_binding)) > 0 ? "none" : length(regexall(
  "static_binding", each.value.port_binding)) > 0 ? "staticBinding" : each.value.port_binding
  allow_micro_seg = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.allow_micro_segmentation : false
  #delimiter = length(
  #  regexall("vmm", each.value.domain_type)
  #) > 0 ? each.value.delimiter : ""
  custom_epg_name = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.custom_epg_name : ""
  encap = each.value.vlan_mode != "dynamic" && length(
    regexall("vmm", each.value.domain_type)
  ) > 0 ? "vlan-${element(each.value.vlans, 0)}" : "unknown"
  encap_mode = each.value.vlan_mode == "static" && length(
  regexall("vmm", each.value.domain_type)) > 0 ? "vlan" : "auto"
  epg_cos             = length(regexall("vmm", each.value.domain_type)) > 0 ? "Cos0" : "Cos0"
  epg_cos_pref        = length(regexall("vmm", each.value.domain_type)) > 0 ? "disabled" : "disabled"
  instr_imedcy        = each.value.deploy_immediacy == "on-demand" ? "lazy" : each.value.deploy_immediacy
  enhanced_lag_policy = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.enhanced_lag_policy : ""
  netflow_dir         = length(regexall("vmm", each.value.domain_type)) > 0 ? "both" : "both"
  netflow_pref        = length(regexall("vmm", each.value.domain_type)) > 0 ? "disabled" : "disabled"
  num_ports = length(regexall("vmm", each.value.domain_type)) > 0 && (length(regexall(
    "dynamic_binding", each.value.port_binding)) > 0 || length(regexall("static_binding", each.value.port_binding)) > 0
  ) ? each.value.number_of_ports : 0
  port_allocation = length(regexall("vmm", each.value.domain_type)) > 0 && length(regexall(
    "static_binding", each.value.port_binding)
  ) > 0 ? each.value.port_allocation : "none"
  primary_encap = length(regexall("vmm", each.value.domain_type)) > 0 && length(regexall( # Represents the primary encap when the EPG is isolated
    "static", each.value.vlan_mode)) > 0 && length(each.value.vlans
  ) >= 1 ? "vlan-${element(each.value.vlans, 0)}" : "unknown"
  primary_encap_inner = length(regexall("vmm", each.value.domain_type)) > 0 && length(regexall(
    "static", each.value.vlan_mode)) > 0 && length(each.value.vlans
  ) >= 2 ? "vlan-${element(each.value.vlans, 1)}" : "unknown"
  res_imedcy = each.value.resolution_immediacy == "on-demand" ? "lazy" : each.value.resolution_immediacy
  secondary_encap_inner = length(regexall("vmm", each.value.domain_type)) > 0 && length(regexall(
    "static", each.value.vlan_mode)) > 0 && length(each.value.vlans
  ) >= 3 ? "vlan-${element(each.value.vlans, 2)}" : "unknown"
  switching_mode        = "native"
  vmm_allow_promiscuous = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.security.allow_promiscuous : ""
  vmm_forged_transmits  = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.security.forged_transmits : ""
  vmm_mac_changes       = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.security.mac_changes : ""
}


#------------------------------------------
# Assign Contract to EPG
#------------------------------------------

/*_____________________________________________________________________________________________________________________

API Information:
* Consumer Contract
 - Class: "fvRsCons"
 - Distinguished Name: "uni/tn-{tenant}/ap-{application_profile}/epg-{epg}/rscons-{contract}"
* Provider Contract
 - Class: "fvRsProv"
 - Distinguished Name: "uni/tn-{tenant}/ap-{application_profile}/epg-{epg}/rsprov-{contract}"
GUI Location:
 - Tenants > {tenant} > Application Profiles > {application_profile} > Application EPGs > {epg} > Contracts
_______________________________________________________________________________________________________________________
*/
# resource "aci_epg_to_contract" "contract_to_epg" {
#     depends_on          = [
#         aci_tenant.tenants,
#         aci_application_epg.application_epgs,
#         aci_contract.contracts
#     ]
#     application_epg_dn  = aci_application_epg.application_epgs[each.value.application_epg].id
#     contract_dn         = length(regexall(
#       "oob", each.value.type)
#       ) > 0 ? aci_rest_managed.oob_contracts[each.value.contract].id : length(regexall(
#       "standard", each.value.type)
#       ) > 0 ? aci_contract.contracts[each.value.contract].id : length(regexall(
#       "taboo", each.value.type)
#     ) > 0 ? apic_taboo_contracts.contracts[each.value.contract].id : ""
#     contract_type       = each.value.type
# }

resource "aci_rest_managed" "contract_to_epgs" {
  depends_on = [
    aci_application_epg.map,
    aci_contract.map,
    aci_taboo_contract.map,
  ]
  for_each   = { for k, v in local.contract_to_epgs : k => v if v.epg_type == "standard" }
  dn         = "uni/tn-${each.value.tenant}/ap-${each.value.application_profile}/epg-${each.value.application_epg}/${each.value.contract_dn}-${each.value.contract}"
  class_name = each.value.contract_class
  content = {
    # matchT = each.value.match_type
    prio = each.value.qos_class
  }
}

resource "aci_rest_managed" "contract_to_oob_epgs" {
  depends_on = [
    aci_node_mgmt_epg.mgmt_epgs,
    aci_contract.map,
    aci_rest_managed.oob_contracts,
    aci_taboo_contract.map,
  ]
  for_each   = { for k, v in local.contract_to_epgs : k => v if v.epg_type == "oob" && v.contract_type == "provided" }
  dn         = "uni/tn-${each.value.tenant}/mgmtp-default/oob-${each.value.application_epg}/${each.value.contract_dn}-${each.value.contract}"
  class_name = each.value.contract_class
  content = {
    #    # matchT = each.value.match_type
    prio = each.value.qos_class
  }
}

resource "aci_rest_managed" "contract_to_inb_epgs" {
  depends_on = [
    aci_node_mgmt_epg.mgmt_epgs,
    aci_contract.map,
    aci_rest_managed.oob_contracts,
    aci_taboo_contract.map,
  ]
  for_each   = { for k, v in local.contract_to_epgs : k => v if v.epg_type == "inb" }
  dn         = "uni/tn-${each.value.tenant}/mgmtp-default/inb-${each.value.application_epg}/${each.value.contract_dn}-${each.value.contract}"
  class_name = each.value.contract_class
  content = {
    #    # matchT = each.value.match_type
    prio = each.value.qos_class
  }
}


#------------------------------------------------
# Assign a Subnet to an Out-of-Band External EPG
#------------------------------------------------

/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "mgmtSubnet"
 - Distinguished Name: "uni/tn-mgmt/extmgmt-default/instp-{ext_epg}/subnet-[{subnet}]"
GUI Location:
 - tenants > mgmt > External Management Network Instance Profiles > {ext_epg}: Subnets:{subnet}
_______________________________________________________________________________________________________________________
*/
# resource "aci_rest_managed" "oob_external_epg_subnets" {
#   depends_on = [
#     aci_rest_managed.oob_external_epgs
#   ]
#   for_each   = { for k, v in local.oob_epg_subnets : k => v if v.epg_type == "oob" }
#   dn         = "uni/tn-mgmt/extmgmt-default/instp-${each.value.epg}/subnet-[${each.value.subnet}]"
#   class_name = "mgmtSubnet"
#   content = {
#     ip = each.value.subnet
#   }
# }


#------------------------------------------------------
# Create Attachable Access Entity Generic Encap Policy
#------------------------------------------------------

/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "infraAttEntityP"
 - Distinguished Name: "uni/infra/attentp-{AAEP}"
GUI Location:
 - Fabric > Access Policies > Policies > Global > Attachable Access Entity Profiles : {AAEP}
_______________________________________________________________________________________________________________________
*/
resource "aci_epgs_using_function" "epg_to_aaeps" {
  depends_on        = [aci_application_epg.map]
  for_each          = { for k, v in local.epg_to_aaeps : k => v if local.controller.type == "apic" }
  access_generic_dn = "uni/infra/attentp-${each.value.aaep}/gen-default"
  encap             = length(each.value.vlans) > 0 ? "vlan-${element(each.value.vlans, 0)}" : "unknown"
  instr_imedcy      = each.value.instrumentation_immediacy == "on-demand" ? "lazy" : each.value.instrumentation_immediacy
  mode              = each.value.mode == "trunk" ? "regular" : each.value.mode == "access" ? "untagged" : "native"
  primary_encap     = length(each.value.vlans) > 1 ? "vlan-${element(each.value.vlans, 1)}" : "unknown"
  tdn               = aci_application_epg.map[each.value.key].id
}


/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "fvRsPathAtt"
 - Distinguished Name: "uni/tn-{tenant}/ap-{application_profile}/epg-{application_epg}/{static_path}"
GUI Location:
Tenants > {tenant} > Application Profiles > {application_profile} > Application EPGs > {application_epg} > Static Ports > {GUI_Static}
_______________________________________________________________________________________________________________________
*/
resource "aci_bulk_epg_to_static_path" "map" {
  depends_on         = [aci_application_epg.map]
  for_each           = { for k, v in local.epg_to_static_paths : k => v if local.controller.type == "apic" && length(v.static_paths) > 0 }
  application_epg_dn = aci_application_epg.map[each.key].id
  dynamic "static_path" {
    for_each = each.value.static_paths
    content {
      deployment_immediacy = static_path.value.instrumentation_immediacy
      encap = length(
        regexall("micro_seg", static_path.value.encapsulation_type)
        ) > 0 ? "vlan-${element(static_path.value.vlans, 0)}" : length(
        regexall("qinq", static_path.value.encapsulation_type)
        ) > 0 ? "qinq-${element(static_path.value.vlans, 0)}-${element(static_path.value.vlans, 1)}" : length(
        regexall("vlan", static_path.value.encapsulation_type)
        ) > 0 ? "vlan-${element(static_path.value.vlans, 0)}" : length(
        regexall("vxlan", static_path.value.encapsulation_type)
      ) > 0 ? "vxlan-${element(static_path.value.vlans, 0)}" : ""
      interface_dn = "${static_path.value.distinguished_name}[${static_path.value.tdn}]"
      mode         = static_path.value.mode == "trunk" ? "regular" : static_path.value.mode == "access" ? "untagged" : "native"
      primary_encap = length(regexall("micro_seg", static_path.value.encapsulation_type)
      ) > 0 ? "vlan-${element(static_path.value.vlans, 1)}" : "unknown"
    }
  }
}


/*_____________________________________________________________________________________________________________________

Nexus Dashboard — Application Endpoint Group
_______________________________________________________________________________________________________________________
*/
resource "mso_schema_template_anp_epg" "map" {
  provider = mso
  depends_on = [
    mso_schema_template_anp.map,
    mso_schema_template_bd.map
  ]
  for_each         = { for k, v in local.application_epgs : k => v if local.controller.type == "ndo" }
  anp_name         = each.value.application_profile
  bd_name          = each.value.bd.name
  bd_schema_id     = data.mso_schema.map[each.value.bd.ndo.schema].id
  bd_template_name = each.value.bd.ndo.template
  description      = each.value.description
  display_name     = length(each.value.combine_description) > 0 ? "${each.value.name}${each.value.combine_description}${each.value.description}" : each.value.name
  intra_epg        = each.value.intra_epg_isolation
  #
  intersite_multicast_source = false
  #
  name            = each.value.name
  preferred_group = each.value.preferred_group_member
  proxy_arp       = each.value.intra_epg_isolation == "enforced" ? true : false
  schema_id       = data.mso_schema.map[each.value.ndo.schema].id
  template_name   = each.value.ndo.template
  useg_epg        = each.value.useg_epg
  #vrf_name                   = each.value.general.vrf.name
  #vrf_schema_id              = data.mso_schema.schemas[each.value.general.vrf.schema].id
  #vrf_template_name          = each.value.general.vrf.template
}

resource "mso_schema_site_anp_epg_domain" "map" {
  provider   = mso
  depends_on = [mso_schema_template_anp_epg.map]
  for_each = {
    for k, v in local.ndo_epg_to_domains : k => v if local.controller.type == "ndo"
  }
  allow_micro_segmentation = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? each.value.allow_micro_segmentation : null
  allow_promiscuous = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? each.value.security.allow_promiscuous : null
  anp_name = each.value.application_profile
  binding_type = each.value.port_binding == "static_binding" && length(
    regexall("vmm", each.value.domain_type)) > 0 ? "static" : each.value.port_binding == "dynamic_binding" && length(
    regexall("vmm", each.value.domain_type)) > 0 ? "dynamic" : each.value.port_binding == "ephemeral" && length(
    regexall("vmm", each.value.domain_type)) > 0 ? each.value.port_binding : length(
  regexall("vmm", each.value.domain_type)) > 0 ? "none" : null
  custom_epg_name = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? each.value.custom_epg_name : null
  delimiter = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? each.value.delimiter : null
  deploy_immediacy = each.value.deploy_immediacy == "on-demand" ? "lazy" : each.value.deploy_immediacy
  domain_name      = each.value.domain
  domain_type      = length(regexall("vmm", each.value.domain_type)) > 0 ? "vmmDomain" : "physicalDomain"
  enhanced_lag_policy_dn = length(regexall("vmm", each.value.domain_type)) > 0 && length(
    compact([each.value.enhanced_lag_policy])
  ) > 0 ? "uni/vmmp-${each.value.switch_provider}/dom-${each.value.domain}/vswitchpolcont/enlacplagp-${each.value.enhanced_lag_policy}" : null
  enhanced_lag_policy_name = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.enhanced_lag_policy : null
  epg_name                 = each.value.application_epg
  forged_transmits = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? each.value.security.forged_transmits : null
  mac_changes = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? each.value.security.mac_changes : null
  micro_seg_vlan = length(regexall("vmm", each.value.domain_type)) > 0 && length(regexall("static", each.value.vlan_mode)
  ) > 0 && length(each.value.vlans) > 1 ? element(each.value.vlans, 2) : null
  micro_seg_vlan_type = length(regexall("vmm", each.value.domain_type)
  ) > 0 && length(regexall("static", each.value.vlan_mode)) > 0 ? "vlan" : null
  netflow = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? "disabled" : null
  num_ports = length(regexall("vmm", each.value.domain_type)) > 0 && (length(regexall(
    "dynamic_binding", each.value.port_binding)) > 0 || length(regexall("static_binding", each.value.port_binding)) > 0
  ) ? each.value.number_of_ports : 0
  port_allocation = length(regexall("vmm", each.value.domain_type)) > 0 && length(regexall(
    "static_binding", each.value.port_binding)
  ) > 0 ? each.value.port_allocation : null
  port_encap_vlan = length(regexall("vmm", each.value.domain_type)) > 0 && length(regexall("static", each.value.vlan_mode)
  ) > 0 && length(each.value.vlans) > 0 ? element(each.value.vlans, 1) : null
  port_encap_vlan_type = length(regexall("vmm", each.value.domain_type)
  ) > 0 && length(regexall("static", each.value.vlan_mode)) > 0 ? "vlan" : null
  resolution_immediacy = each.value.resolution_immediacy == "on-demand" ? "lazy" : each.value.resolution_immediacy
  schema_id            = data.mso_schema.map[each.value.ndo.schema].id
  site_id              = data.mso_site.map[each.value.site].id
  switch_type          = length(regexall("vmm", each.value.domain_type)) > 0 ? "default" : null
  switching_mode       = length(regexall("vmm", each.value.domain_type)) > 0 ? "native" : null
  template_name        = each.value.ndo.template
  vlan_encap_mode = length(regexall("vmm", each.value.domain_type)
  ) > 0 ? each.value.vlan_mode : null
  vmm_domain_type = length(regexall("vmm", each.value.domain_type)) > 0 ? each.value.switch_provider : null
  lifecycle {
    ignore_changes = [
      schema_id,
      site_id
    ]
  }
}

resource "mso_schema_template_anp_epg_contract" "map" {
  provider               = mso
  depends_on             = [mso_schema_template_anp_epg.map]
  for_each               = { for k, v in local.contract_to_epgs : k => v if local.controller.type == "ndo" }
  anp_name               = each.value.application_profile
  epg_name               = each.value.application_epg
  contract_name          = each.value.contract
  contract_schema_id     = data.mso_schema.map[each.value.ndo.contract_schema].id
  contract_template_name = each.value.ndo.contract_template
  relationship_type      = each.value.type
  schema_id              = data.mso_schema.map[each.value.ndo.schema].id
  template_name          = each.value.ndo.template
  lifecycle { ignore_changes = [contract_schema_id, schema_id] }
}

resource "mso_schema_site_anp_epg_bulk_staticport" "map" {
  provider      = mso
  depends_on    = [mso_schema_template_anp_epg.map]
  for_each      = { for k, v in local.ndo_epg_to_static_paths : k => v if local.controller.type == "ndo" && length(v.static_paths) > 0 }
  anp_name      = each.value.application_profile
  epg_name      = each.value.application_epg
  schema_id     = data.mso_schema.map[each.value.ndo.schema].id
  site_id       = data.mso_site.map[each.value.site].id
  template_name = each.value.ndo.template
  dynamic "static_ports" {
    for_each = { for v in each.value.static_paths : "${v.pod_id}/${v.leaf}/${v.interface}" => v }
    content {
      deployment_immediacy = static_ports.value.instrumentation_immediacy
      leaf                 = static_ports.value.leaf
      micro_seg_vlan = static_ports.value.encapsulation_type == "micro_seg" && length(static_ports.value.vlans
      ) == 2 ? element(static_ports.value.vlans, 1) : null
      mode      = static_ports.value.mode == "trunk" ? "regular" : static_ports.value.mode == "access" ? "untagged" : "native"
      path      = length(regexall("vpc|dpc", static_ports.value.interface)) > 0 ? static_ports.value.interface : "eth${static_ports.value.interface}"
      path_type = static_ports.value.path_type
      pod       = "pod-${static_ports.value.pod_id}"
      vlan      = element(static_ports.value.vlans, 0)
    }
  }
  lifecycle {
    ignore_changes = [
      schema_id,
      site_id
    ]
  }
}