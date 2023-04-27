#!/bin/sh
random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}

install_squid() {
    echo "installing squid"
    yum -y install squid
    systemctl start squid

    chkconfig squid on
    cd $WORKDIR
}

gen_squid_conf() {
    cat <<EOF

# Recommended minimum configuration:

# Example rule allowing access from your local networks.
# Adapt to list your (internal) IP networks from where browsing
# should be allowed
#acl localnet src 10.0.0.0/8	# RFC1918 possible internal network
#acl localnet src 172.16.0.0/12	# RFC1918 possible internal network
#acl localnet src 192.168.0.0/16	# RFC1918 possible internal network
#acl localnet src fc00::/7       # RFC 4193 local private network range
#acl localnet src fe80::/10      # RFC 4291 link-local (directly plugged) machines


#acl SSL_ports port 443
#acl Safe_ports port 80		# http
#acl Safe_ports port 21		# ftp
#acl Safe_ports port 443		# https
#acl Safe_ports port 70		# gopher
#acl Safe_ports port 210		# wais
#acl Safe_ports port 1025-65535	# unregistered ports
#acl Safe_ports port 280		# http-mgmt
#acl Safe_ports port 488		# gss-http
#acl Safe_ports port 591		# filemaker
#acl Safe_ports port 777		# multiling http
#acl CONNECT method CONNECT

# ...Cau Hinh Authenticate Cho Proxy Theo Users..

auth_param basic program /usr/lib64/squid/basic_ncsa_auth /etc/squid/user_passwords
auth_param basic children 5
auth_param basic realm Squid Basic Authentication
auth_param basic credentialsttl 2 hours
acl auth_users proxy_auth REQUIRED
http_access allow auth_users
# ................................................

#
# Recommended minimum Access Permission configuration:
#
# Deny requests to certain unsafe ports
#http_access deny !Safe_ports

# Deny CONNECT to other than secure SSL ports
#http_access deny CONNECT !SSL_ports

# Only allow cachemgr access from localhost
#http_access allow localhost manager
#http_access deny manager

#allow all internet
#http_access allow all


# We strongly recommend the following be uncommented to protect innocent
# web applications running on the proxy server who think the only
# one who can access services on "localhost" is a local user
#http_access deny to_localhost

#
# INSERT YOUR OWN RULE(S) HERE TO ALLOW ACCESS FROM YOUR CLIENTS
#

# Example rule allowing access from your local networks.
# Adapt localnet in the ACL section to list your (internal) IP networks
# from where browsing should be allowed
#http_access allow localnet
#http_access allow localhost

# And finally deny all other access to this proxy
#http_access deny all
#http_access allow all

# Squid normally listens to port 3128
#http_port 3128
#http_port 10000

$(gen_support_port)

# Config acl
$(gen_port_acl)

# Config tcp_outgoing_address
$(gen_tcp_outgoing_address)

# Connect user - acl
$(awk -F "/" '{print "acl " $1 "_user proxy_auth " $1}' ${USERSDATA}) 

# Allow two acl bindings to access:
# user bach0 and port 10000

$(awk -F "/" '{print "http_access allow " $1 "_user " $4}' ${USERSDATA}) 

http_access deny all

# Uncomment and adjust the following to add a disk cache directory.
#cache_dir ufs /var/spool/squid 100 16 256

# Leave coredumps in the first cache dir
coredump_dir /var/spool/squid

#
# Add any of your own refresh_pattern entries above these.
#
refresh_pattern ^ftp:		1440	20%	10080
refresh_pattern ^gopher:	1440	0%	1440
refresh_pattern -i (/cgi-bin/|\?) 0	0%	0
refresh_pattern .		0	20%	4320
EOF
}

gen_users() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)_$port/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${USERSDATA})
EOF
}

upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"

}

gen_support_port() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "http_port ${IP4}:${port}"
    done
}

gen_port_acl() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "acl port${port} myport ${port}"
    done
}

gen_tcp_outgoing_address() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "tcp_outgoing_address $(gen64 $IP6) port$port"
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}


echo "installing apps"
yum -y install gcc net-tools bsdtar zip >/dev/null

install_squid

echo "working folder = proxy-installer"
WORKDIR="proxy-installer"

echo "Create users"
USERSDATA="${WORKDIR}/user_passwords.txt"
touch $WORKDIR/user_passwords.txt
cat $WORKDIR/user_passwords.txt

# USERACL="${WORKDIR}/user_acls.txt"
# OUTGOINGADDRESS="${WORKDIR}/tcp_outgoing_addresses.txt"
# ACLLINKUSERS="${WORKDIR}/acl_link_users.txt"

mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

echo "How many proxy do you want to create? Example 500"
read COUNT

FIRST_PORT=10000
LAST_PORT=$(($FIRST_PORT + $COUNT))

gen_users >$WORKDIR/user_passwords.txt

gen_squid_conf >/etc/squid/squid.conf

echo "Restart squid"

systemctl restart squid

# gen_iptables >$WORKDIR/boot_iptables.sh
# gen_ifconfig >$WORKDIR/boot_ifconfig.sh
# chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local


# cat >>/etc/rc.local <<EOF
# bash ${WORKDIR}/boot_iptables.sh
# bash ${WORKDIR}/boot_ifconfig.sh
# ulimit -n 10048
# service 3proxy start
# EOF

# bash /etc/rc.local

gen_proxy_file_for_user
upload_proxy
