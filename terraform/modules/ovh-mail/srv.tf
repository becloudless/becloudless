

resource "ovh_domain_zone_record" "domain_tld_txt" {
  zone      = var.domain
  fieldtype = "TXT"
  ttl       = "600"
  target    = "\"v=spf1 mx a:${var.mail_domain} ~all\""
}

resource "ovh_domain_zone_record" "domain_tld_mx" {
  zone      = var.domain
  fieldtype = "MX"
  ttl       = "600"
  target    = "1 ${var.mail_domain}."
}

resource "ovh_domain_zone_record" "domain_tld_dkim" {
  zone      = var.domain
  subdomain = "dkim._domainkey"
  fieldtype = "DKIM"
  ttl       = "600"
  target    = "v=DKIM1; k=rsa; p=${var.dkim_p}"
}

resource "ovh_domain_zone_record" "dmark_domain_tld_txt" {
  zone      = var.domain
  subdomain = "_dmarc"
  fieldtype = "TXT"
  ttl       = "600"
  target    = "\"v=DMARC1; p=reject; adkim=s; aspf=s\""
}

resource "ovh_domain_zone_record" "report_dmark_domain_tld_txt" {
  zone      = var.domain
  subdomain = "${var.domain}._report._dmarc"
  fieldtype = "TXT"
  ttl       = "600"
  target    = "\"v=DMARC1\""
}

resource "ovh_domain_zone_record" "imaps_domain_tld_srv" {
  zone      = var.domain
  subdomain = "_imaps._tcp"
  fieldtype = "SRV"
  ttl       = "600"
  target    = "1 1 993 ${var.mail_domain}."
}

resource "ovh_domain_zone_record" "imap_domain_tld_srv" {
  zone      = var.domain
  subdomain = "_imap._tcp"
  fieldtype = "SRV"
  ttl       = "600"
  target    = "1 1 143 ${var.mail_domain}."
}

resource "ovh_domain_zone_record" "pop3s_domain_tld_srv" {
  zone      = var.domain
  subdomain = "_pop3s._tcp"
  fieldtype = "SRV"
  ttl       = "600"
  target    = "1 1 995 ${var.mail_domain}."
}

resource "ovh_domain_zone_record" "pop3_domain_tld_srv" {
  zone      = var.domain
  subdomain = "_pop3._tcp"
  fieldtype = "SRV"
  ttl       = "600"
  target    = "1 1 110 ${var.mail_domain}."
}

resource "ovh_domain_zone_record" "submission_domain_tld_srv" {
  zone      = var.domain
  subdomain = "_submission._tcp"
  fieldtype = "SRV"
  ttl       = "600"
  target    = "1 1 587 ${var.mail_domain}."
}
