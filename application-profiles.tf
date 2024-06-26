/*_____________________________________________________________________________________________________________________

API Location:
 - Class: "fvAp"
 - Distinguished Name: "uni/tn-[tenant]/ap-{application_profile}"
GUI Location:
 - Tenants > {tenant} > Application Profiles > {application_profile}
_______________________________________________________________________________________________________________________
*/
resource "aci_application_profile" "map" {
  depends_on = [aci_tenant.map]
  for_each = {
    for k, v in local.application_profiles : k => v if local.controller.type == "apic" && v.create == true
  }
  tenant_dn   = "uni/tn-${each.value.tenant}"
  description = each.value.description
  name        = each.key
  name_alias  = each.value.alias
  prio        = each.value.qos_class
  relation_fv_rs_ap_mon_pol = length(compact([each.value.monitoring_policy])
  ) > 0 ? "uni/tn-common/monepg-${each.value.monitoring_policy}" : ""
}


/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "tagAnnotation"
 - Distinguished Name: "uni/tn-{tenant}/ap-{application_profile}/annotationKey-[{key}]"
GUI Location:
 - Tenants > {tenant} > Application Profiles > {application_profile}: {annotations}
_______________________________________________________________________________________________________________________
*/
resource "aci_rest_managed" "application_profiles_annotations" {
  depends_on = [aci_application_profile.map]
  for_each = {
    for i in flatten([
      for k, v in local.application_profiles : [
        for e in v.annotations : { application_profile = k, create = v.create, key = e.key, tenant = v.tenant, value = e.value }
      ]
    ]) : "${i.application_profile}:${i.key}" => i if local.controller.type == "apic" && i.create == true
  }
  dn         = "uni/tn-${each.value.tenant}/ap-${each.value.application_profile}/annotationKey-[${each.value.key}]"
  class_name = "tagAnnotation"
  content = {
    key   = each.value.key
    value = each.value.value
  }
}


/*_____________________________________________________________________________________________________________________

API Information:
 - Class: "tagAliasInst"
 - Distinguished Name: "uni/tn-{tenant}/ap-{application_profile}/alias"
GUI Location:
 - Tenants > {tenant} > Application Profiles > {application_profile}: global_alias

_______________________________________________________________________________________________________________________
*/
resource "aci_rest_managed" "application_profiles_global_alias" {
  depends_on = [aci_application_profile.map]
  for_each   = { for k, v in local.application_profiles : k => v if v.global_alias != "" && local.controller.type == "apic" }
  class_name = "tagAliasInst"
  dn         = "uni/tn-${each.key}/ap-${each.value.application_profile}/alias"
  content = {
    name = each.value.global_alias
  }
}


/*_____________________________________________________________________________________________________________________

Nexus Dashboard — Application Profiles
_______________________________________________________________________________________________________________________
*/
resource "mso_schema_template_anp" "map" {
  provider     = mso
  for_each     = { for k, v in local.application_profiles : k => v if local.controller.type == "ndo" && v.create == true }
  display_name = each.key
  name         = each.key
  schema_id    = data.mso_schema.map[each.value.ndo.schema].id
  template     = each.value.ndo.template
  lifecycle {
    ignore_changes = [
      schema_id
    ]
  }
}
