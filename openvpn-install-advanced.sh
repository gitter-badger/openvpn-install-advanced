#!/bin/bash
# OpenVPN road warrior installer for Debian, Ubuntu and CentOS

# This script will work on Debian, Ubuntu, CentOS and probably other distros
# of the same families, although no support is offered for them. It isn't
# bulletproof but it will probably work if you simply want to setup a VPN on
# your Debian/Ubuntu/CentOS box. It has been designed to be as unobtrusive and
# universal as possible.


if [[ "$USER" != 'root' ]]; then
	echo "Sorry, you need to run this as root"
	exit
fi


if [[ ! -e /dev/net/tun ]]; then
	echo "TUN/TAP is not available"
	exit
fi


if grep -qs "CentOS release 5" "/etc/redhat-release"; then
	echo "CentOS 5 is too old and not supported"
	exit
fi

if [[ -e /etc/debian_version ]]; then
	OS=debian
	RCLOCAL='/etc/rc.local'
elif [[ -e /etc/centos-release || -e /etc/redhat-release ]]; then
	OS=centos
	RCLOCAL='/etc/rc.d/rc.local'
	# Needed for CentOS 7
	chmod +x /etc/rc.d/rc.local
else
	echo "Looks like you aren't running this installer on a Debian, Ubuntu or CentOS system"
	exit
fi

newclient () {
        # Generates the custom client.ovpn
        cp /etc/openvpn/client-common.txt ~/$1.ovpn
        echo "<ca>" >> ~/$1.ovpn
        cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1.ovpn
        echo "</ca>" >> ~/$1.ovpn
        echo "<cert>" >> ~/$1.ovpn
        cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn
        echo "</cert>" >> ~/$1.ovpn
        echo "<key>" >> ~/$1.ovpn
        cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1.ovpn
        echo "</key>" >> ~/$1.ovpn
        if [ "$TLS" = "1" ]; then
		echo "key-direction 1" >> ~/$1.ovpn
        echo "<tls-auth>" >> ~/$1.ovpn
        cat /etc/openvpn/easy-rsa/pki/private/ta.key >> ~/$1.ovpn
        echo "</tls-auth>" >> ~/$1.ovpn
		fi
        
}


newclienttcp () {
	# Generates the custom client.ovpn
	cp /etc/openvpn/clienttcp-common.txt ~/$1tcp.ovpn
	echo "<ca>" >> ~/$1tcp.ovpn
	cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1tcp.ovpn
	echo "</ca>" >> ~/$1tcp.ovpn
	echo "<cert>" >> ~/$1tcp.ovpn
	cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1tcp.ovpn
	echo "</cert>" >> ~/$1tcp.ovpn
	echo "<key>" >> ~/$1tcp.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1tcp.ovpn
	echo "</key>" >> ~/$1tcp.ovpn
	if [ "$TLS" = "1" ]; then
	echo "key-direction 1" >> ~/$1tcp.ovpn
	echo "<tls-auth>" >> ~/$1tcp.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/ta.key >> ~/$1tcp.ovpn
	echo "</tls-auth>" >> ~/$1tcp.ovpn
	fi
	
}


# Try to get our IP from the system and fallback to the Internet.
# I do this to make the script compatible with NATed servers (lowendspirit.com)
# and to avoid getting an IPv6.
IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
if [[ "$IP" = "" ]]; then
		IP=$(wget -qO- ipv4.icanhazip.com)
fi


if [ -e /etc/openvpn/udp.conf -o -e /etc/openvpn/tcp.conf ]; then    #changed from server.conf to anything
	while :
	do
	clear
		echo "Looks like OpenVPN is already installed"
		echo ""
		echo "What do you want to do?"
		echo "   1) Add a cert for a new user"
		echo "   2) Revoke existing user cert"
		echo "   3) Remove OpenVPN"
		echo "   4) Exit"
		read -p "Select an option [1-4]: " option
		case $option in
			1) 
			echo ""
			echo "Tell me a name for the client cert"
			echo "Please, use one word only, no special characters"
			read -p "Client name: " -e -i client CLIENT
			cd /etc/openvpn/easy-rsa/
			./easyrsa build-client-full $CLIENT nopass
			# Generates the custom client.ovpn
			if [[ -e /etc/openvpn/udp.conf ]]; then
			TLS=0
			if [ -n "$(cat /etc/openvpn/udp.conf | grep tls-auth)" ]; then
			TLS=1
			fi 
			newclient "$CLIENT"
			
			fi
			if [[ -e /etc/openvpn/tcp.conf ]]; then
			TLS=0
			if [ -n "$(cat /etc/openvpn/tcp.conf | grep tls-auth)" ]; then
			TLS=1
			fi 
			newclienttcp "$CLIENT"
			fi
			
			echo ""
			echo "Client $CLIENT added, certs available at ~/$CLIENT.ovpn"
			exit
			;;
			2)
			# This option could be documented a bit better and maybe even be simplimplified
			# ...but what can I say, I want some sleep too
			NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
			if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
				echo ""
				echo "You have no existing clients!"
				exit
			fi
			echo ""
			echo "Select the existing client certificate you want to revoke"
			tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | nl -s ') '
			if [[ "$NUMBEROFCLIENTS" = '1' ]]; then
				read -p "Select one client [1]: " CLIENTNUMBER
			else
				read -p "Select one client [1-$NUMBEROFCLIENTS]: " CLIENTNUMBER
			fi
			CLIENT=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | sed -n "$CLIENTNUMBER"p)
			cd /etc/openvpn/easy-rsa/
			./easyrsa --batch revoke $CLIENT
			./easyrsa gen-crl
			# And restart
			if pgrep systemd-journal; then
				sudo systemctl restart udp.service
                sudo systemctl restart tcp.service
			else
				if [[ "$OS" = 'debian' ]]; then
					/etc/init.d/openvpn restart
				else
					service openvpn restart
				fi
			fi
			echo ""
			echo "Certificate for client $CLIENT revoked"
			exit
			;;
			3) 
			echo ""
			read -p "Do you really want to remove OpenVPN? [y/n]: " -e -i n REMOVE
			if [[ "$REMOVE" = 'y' ]]; then
			if [[ -e /etc/openvpn/udp.conf ]]; then
				PORT=$(grep '^port ' /etc/openvpn/udp.conf | cut -d " " -f 2)
				if pgrep firewalld; then
					# Using both permanent and not permanent rules to avoid a firewalld reload.
					firewall-cmd --zone=public --remove-port=$PORT/udp
					firewall-cmd --zone=trusted --remove-source=10.8.0.0/24
					firewall-cmd --permanent --zone=public --remove-port=$PORT/udp
					firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24
				fi
				if iptables -L | grep -q REJECT; then
					sed -i "/iptables -I INPUT -p udp --dport $PORT -j ACCEPT/d" $RCLOCAL
					sed -i "/iptables -I FORWARD -s 10.8.0.0\/24 -j ACCEPT/d" $RCLOCAL
					sed -i "/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT/d" $RCLOCAL
				fi
				sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0\/24 -j SNAT --to /d' $RCLOCAL
				fi
				
				if [[ -e /etc/openvpn/tcp.conf ]]; then
				PORT=$(grep '^port ' /etc/openvpn/udp.conf | cut -d " " -f 2)
				if pgrep firewalld; then
					# Using both permanent and not permanent rules to avoid a firewalld reload.
					firewall-cmd --zone=public --remove-port=$PORT/udp
					firewall-cmd --zone=trusted --remove-source=1.8.0.0/24
					firewall-cmd --permanent --zone=public --remove-port=$PORT/udp
					firewall-cmd --permanent --zone=trusted --remove-source=1.8.0.0/24
				fi
				if iptables -L | grep -q REJECT; then
					sed -i "/iptables -I INPUT -p udp --dport $PORT -j ACCEPT/d" $RCLOCAL
					sed -i "/iptables -I FORWARD -s 1.8.0.0\/24 -j ACCEPT/d" $RCLOCAL
					sed -i "/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT/d" $RCLOCAL
				fi
				sed -i '/iptables -t nat -A POSTROUTING -s 1.8.0.0\/24 -j SNAT --to /d' $RCLOCAL
				fi
				if [[ "$OS" = 'debian' ]]; then
					apt-get remove --purge -y openvpn openvpn-blacklist
				else
					yum remove openvpn -y
				fi
				rm -rf /etc/openvpn
				rm -rf /usr/share/doc/openvpn*
				echo ""
				echo "OpenVPN removed!"
			else
				echo ""
				echo "Removal aborted!"
			fi
			exit
			;;
			4) exit;;
		esac
	done
else
	clear
	echo 'Welcome to this quick OpenVPN "road warrior" installer'
	echo ""
	# OpenVPN setup and first user creation
	echo "I need to ask you a few questions before starting the setup"
	echo "You can leave the default options and just press enter if you are ok with them"
	echo ""
	echo "First I need to know the IPv4 address of the network interface you want OpenVPN"
	echo "listening to."
	read -p "IP address: " -e -i $IP IP
	echo ""
	while :
	do
	while :
	do
	clear
	echo "Do you want UDP server?"
	read -p "y or n " -e -i y UDP
        case $UDP in
	       y)	UDP=1
	    break ;;
	       n)   UDP=0
	     break ;;
        esac
	 done
	 
	 while :
	do
	clear
	echo "Do you want TCP server?"
	read -p "y or n " -e -i y TCP
        case $TCP in
	       y)	TCP=1
	    break ;;
	       n)   TCP=0
	     break ;;
        esac
	 done
	 if [ "$UDP" = 1 -o "$TCP" = 1 ]; then
	  break
	  fi
	 done
	 if [ "$UDP" = 1 ]; then
	echo "What UDP port do you want for OpenVPN?"
	read -p "Port: " -e -i 1194 PORT
	 fi
	 if [ "$TCP" = 1 ]; then
	echo  "What TCP port do you want for OpenVPN?"
	read -p "Port: " -e -i 443 PORTTCP
	 fi
       while :
	do
	clear
	     
	read -p "Do you want 2048bit or 4096bit key size? " -e -i 2048 KEYSIZE
	 case $KEYSIZE in
	    2048) KEYSIZE=2048
		 break ;;
		4096) KEYSIZE=4096
         break ;;
     esac		 
	done
	
	 while :
	do
	clear
	     
	read -p "Do you want 256bit or 512bit SHA digest? " -e -i 256 DIGEST
	 case $DIGEST in
		256) DIGEST=SHA256
         break ;;
        512) DIGEST=SHA512
          break ;;	
        esac		  
	done 
	
	while :
	do
	clear
	 echo "Which cipher do you want to use? :"
	 echo "     1) AES-256-CBC"
	 echo "     2) AES-128-CBC"
	 echo "     3) BF-CBC"
	 echo "     4) CAMELLIA-256-CBC"
	 echo "     5) CAMELLIA-128-CBC"
	 echo ""    
	read -p "" -e -i 1 CIPHER
	 case $CIPHER in
	    1) CIPHER=AES-256-CBC
		 break ;;
		2) CIPHER=AES-128-CBC
         break ;;
        3) CIPHER=BF-CBC
         break ;;	
        4) CIPHER=CAMELLIA-256-CBC
         break ;;
        5) CIPHER=CAMELLIA-128-CBC
         break ;;
        esac		  
	done   
    while :
    do
    clear
    read -p "Do you want to use additional TLS authentication(y/n): " -e -i y TLS
     case $TLS in
      y) TLS=1
      break ;;
      n) TLS=0
      break ;;
      esac
      done
	echo ""
	echo "What DNS do you want to use with the VPN?"
	echo "   1) Current system resolvers"
	echo "   2) OpenDNS"
	echo "   3) Level 3"
	echo "   4) NTT"
	echo "   5) Hurricane Electric"
	echo "   6) Google"
	read -p "DNS [1-6]: " -e -i 1 DNS
	echo ""
	echo "Finally, tell me your name for the client cert"
	echo "Please, use one word only, no special characters"
	read -p "Client name: " -e -i client CLIENT
	echo ""
	echo "Okay, that was all I needed. We are ready to setup your OpenVPN server now"
	read -n1 -r -p "Press any key to continue..."
		if [[ "$OS" = 'debian' ]]; then
		apt-get update
		apt-get install openvpn iptables openssl -y
	else
		# Else, the distro is CentOS
		yum install epel-release -y
		yum install openvpn iptables openssl wget -y
	fi
	# An old version of easy-rsa was available by default in some openvpn packages
	if [[ -d /etc/openvpn/easy-rsa/ ]]; then
		rm -rf /etc/openvpn/easy-rsa/
	fi
	# Get easy-rsa
	wget --no-check-certificate -O ~/EasyRSA-3.0.0.tgz https://github.com/OpenVPN/easy-rsa/releases/download/3.0.0/EasyRSA-3.0.0.tgz
	tar xzf ~/EasyRSA-3.0.0.tgz -C ~/
	mv ~/EasyRSA-3.0.0/ /etc/openvpn/
	mv /etc/openvpn/EasyRSA-3.0.0/ /etc/openvpn/easy-rsa/
	chown -R root:root /etc/openvpn/easy-rsa/
	rm -rf ~/EasyRSA-3.0.0.tgz
	cd /etc/openvpn/easy-rsa/
	# Create the PKI, set up the CA, the DH params and the server + client certificates
	./easyrsa init-pki
	cp vars.example vars
	  #change key size to 4096 bit
	sed -i 's/#set_var EASYRSA_KEY_SIZE	2048/set_var EASYRSA_KEY_SIZE   '$KEYSIZE'/' vars
	./easyrsa --batch build-ca nopass
	./easyrsa gen-dh
	./easyrsa build-server-full server nopass
	./easyrsa build-client-full $CLIENT nopass
	./easyrsa gen-crl
   
	openvpn --genkey --secret /etc/openvpn/easy-rsa/pki/private/ta.key    #generate TLS key for additional security
	
     
	# Move the stuff we need
	cp pki/ca.crt pki/private/ca.key pki/dh.pem pki/issued/server.crt pki/private/server.key /etc/openvpn
	if [ "$UDP" = 1 ]; then
	# Generate udp.conf
	echo "port $PORT
proto udp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
topology subnet
server 10.8.0.0 255.255.255.0
cipher $CIPHER
auth $DIGEST
ifconfig-pool-persist ipp.txt" > /etc/openvpn/udp.conf
	echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/udp.conf
	if [ $TLS = 1 ]; then
	echo "--tls-auth /etc/openvpn/easy-rsa/pki/private/ta.key 0" >> /etc/openvpn/udp.conf
	fi
	# DNS
	case $DNS in
		1) 
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/udp.conf
		done
		;;
		2)
		echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/udp.conf
		echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/udp.conf
		;;
		3) 
		echo 'push "dhcp-option DNS 4.2.2.2"' >> /etc/openvpn/udp.conf
		echo 'push "dhcp-option DNS 4.2.2.4"' >> /etc/openvpn/udp.conf
		;;
		4) 
		echo 'push "dhcp-option DNS 129.250.35.250"' >> /etc/openvpn/udp.conf
		echo 'push "dhcp-option DNS 129.250.35.251"' >> /etc/openvpn/udp.conf
		;;
		5) 
		echo 'push "dhcp-option DNS 74.82.42.42"' >> /etc/openvpn/udp.conf
		;;
		6) 
		echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/udp.conf
		echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/udp.conf
		;;
	esac
	echo "keepalive 10 120
comp-lzo
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify /etc/openvpn/easy-rsa/pki/crl.pem" >> /etc/openvpn/udp.conf
 fi 
 if [ "$TCP" = 1 ]; then
echo "port $PORTTCP
proto tcp
dev tun
ca ca.crt
cert server.crt
key server.key
dh dh.pem
topology subnet
server 1.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt
cipher $CIPHER
auth $DIGEST
sndbuf 0
rcvbuf 0" > /etc/openvpn/tcp.conf
	echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/tcp.conf
	
	if [ $TLS = 1 ]; then
	echo "--tls-auth /etc/openvpn/easy-rsa/pki/private/ta.key 0" >> /etc/openvpn/tcp.conf
	fi	
	# DNS
	case $DNS in
		1) 
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		grep -v '#' /etc/resolv.conf | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/tcp.conf
		done
		;;
		2)
		echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/tcp.conf
		echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/tcp.conf
		;;
		3) 
		echo 'push "dhcp-option DNS 4.2.2.2"' >> /etc/openvpn/tcp.conf
		echo 'push "dhcp-option DNS 4.2.2.4"' >> /etc/openvpn/tcp.conf
		;;
		4) 
		echo 'push "dhcp-option DNS 129.250.35.250"' >> /etc/openvpn/tcp.conf
		echo 'push "dhcp-option DNS 129.250.35.251"' >> /etc/openvpn/tcp.conf
		;;
		5) 
		echo 'push "dhcp-option DNS 74.82.42.42"' >> /etc/openvpn/tcp.conf
		;;
		6) 
		echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/tcp.conf
		echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/tcp.conf
		;;
	esac
	echo "keepalive 10 120
comp-lzo
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify /etc/openvpn/easy-rsa/pki/crl.pem" >> /etc/openvpn/tcp.conf
 fi


	# Enable net.ipv4.ip_forward for the system
	if [[ "$OS" = 'debian' ]]; then
		sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf
	else
		# CentOS 5 and 6
		sed -i 's|net.ipv4.ip_forward = 0|net.ipv4.ip_forward = 1|' /etc/sysctl.conf
		# CentOS 7
		if ! grep -q "net.ipv4.ip_forward=1" "/etc/sysctl.conf"; then
			echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
		fi
	fi
	# Avoid an unneeded reboot
	echo 1 > /proc/sys/net/ipv4/ip_forward
	# Set NAT for the VPN subnet
	    if [ "$UDP" = 1 ]; then
	iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP
	sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
	    fi
		if [ "$TCP" = 1 ]; then
	iptables -t nat -A POSTROUTING -s 1.8.0.0/24 -j SNAT --to $IP #This line and the next one are added for tcp server instance
	sed -i "1 a\iptables -t nat -A POSTROUTING -s 1.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
	    fi
	if pgrep firewalld; then
		# We don't use --add-service=openvpn because that would only work with
		# the default port. Using both permanent and not permanent rules to
		# avoid a firewalld reload.
		if [ "$UDP" = 1 ]; then
		firewall-cmd --zone=public --add-port=$PORT/udp
		firewall-cmd --zone=trusted --add-source=10.8.0.0/24
		firewall-cmd --permanent --zone=public --add-port=$PORT/udp
		firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
		fi
		if [ "$TCP" = 1 ]; then
		firewall-cmd --zone=public --add-port=$PORTTCP/tcp  #This line and next 3 lines have been added for tcp support
		firewall-cmd --zone=trusted --add-source=1.8.0.0/24
		firewall-cmd --permanent --zone=public --add-port=$PORTTCP/tcp
		firewall-cmd --permanent --zone=trusted --add-source=1.8.0.0/24
		fi
	fi
	if iptables -L | grep -q REJECT; then
		# If iptables has at least one REJECT rule, we asume this is needed.
		# Not the best approach but I can't think of other and this shouldn't
		# cause problems.
		if [ "$UDP" = 1 ]; then
		iptables -I INPUT -p udp --dport $PORT -j ACCEPT
		iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
		iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
		sed -i "1 a\iptables -I INPUT -p udp --dport $PORT -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL
		fi
		if [ "$TCP" = 1 ]; then
		iptables -I INPUT -p udp --dport $PORTTCP -j ACCEPT #This line and next 5 lines have been added for tcp support
		iptables -I FORWARD -s 1.8.0.0/24 -j ACCEPT
		iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
		sed -i "1 a\iptables -I INPUT -p tcp --dport $PORTTCP -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -s 1.8.0.0/24 -j ACCEPT" $RCLOCAL
		sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL
		fi
	fi
	# And finally, restart OpenVPN
	if [[ "$OS" = 'debian' ]]; then
		# Little hack to check for systemd
		if pgrep systemd-journal; then
			if [ "$UDP" = 1 ]; then
			echo "[Unit]
Description=OpenVPN Robust And Highly Flexible Tunneling Application On <server>
After=syslog.target network.target

[Service]
Type=forking
PIDFile=/var/run/openvpn/udp.pid
ExecStart=/usr/sbin/openvpn --daemon --writepid /var/run/openvpn/udp.pid --cd /etc/openvpn/ --config udp.conf

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/udp.service
           sudo systemctl enable udp.service
		   sudo systemctl start udp.service
		   fi
		   
		   if [ "$TCP" = 1 ]; then
echo "[Unit]
Description=OpenVPN Robust And Highly Flexible Tunneling Application On <server>
After=syslog.target network.target

[Service]
Type=forking
PIDFile=/var/run/openvpn/tcp.pid
ExecStart=/usr/sbin/openvpn --daemon --writepid /var/run/openvpn/tcp.pid --cd /etc/openvpn/ --config tcp.conf

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/tcp.service
sudo systemctl enable tcp.service
sudo systemctl start tcp.service
			fi
			#systemctl restart openvpn@server.service
		else
			/etc/init.d/openvpn restart
		fi
	else
		if pgrep systemd-journal; then
			if [ "$UDP" = 1 ]; then
			echo "[Unit]
Description=OpenVPN Robust And Highly Flexible Tunneling Application On <server>
After=syslog.target network.target

[Service]
Type=forking
PIDFile=/var/run/openvpn/udp.pid
ExecStart=/usr/sbin/openvpn --daemon --writepid /var/run/openvpn/udp.pid --cd /etc/openvpn/ --config udp.conf

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/udp.service
           sudo systemctl enable udp.service
		   sudo systemctl start udp.service
		   fi
		   
		   if [ "$TCP" = 1 ]; then
echo "[Unit]
Description=OpenVPN Robust And Highly Flexible Tunneling Application On <server>
After=syslog.target network.target

[Service]
Type=forking
PIDFile=/var/run/openvpn/tcp.pid
ExecStart=/usr/sbin/openvpn --daemon --writepid /var/run/openvpn/tcp.pid --cd /etc/openvpn/ --config tcp.conf

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/tcp.service
sudo systemctl enable tcp.service
sudo systemctl start tcp.service
			fi
		else
			service openvpn restart
			chkconfig openvpn on
		fi
	fi
	# Try to detect a NATed connection and ask about it to potential LowEndSpirit users
	EXTERNALIP=$(wget -qO- ipv4.icanhazip.com)
	if [[ "$IP" != "$EXTERNALIP" ]]; then
		echo ""
		echo "Looks like your server is behind a NAT!"
		echo ""
		echo "If your server is NATed (LowEndSpirit), I need to know the external IP"
		echo "If that's not the case, just ignore this and leave the next field blank"
		read -p "External IP: " -e USEREXTERNALIP
		if [[ "$USEREXTERNALIP" != "" ]]; then
			IP=$USEREXTERNALIP
		fi
	fi
	# client-common.txt is created so we have a template to add further users later
	if [ "$UDP" = 1 ]; then
	echo "client
dev tun
cipher $CIPHER
auth $DIGEST
proto udp
remote $IP $PORT
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
comp-lzo
verb 3" > /etc/openvpn/client-common.txt
newclient "$CLIENT"
  fi
    if [ "$TCP" = 1 ]; then
	echo "client  
	cipher $CIPHER
auth $DIGEST
dev tun
proto tcp
remote $IP $PORTTCP
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
comp-lzo
verb 3
sndbuf 0
rcvbuf 0
" > /etc/openvpn/clienttcp-common.txt  #clienttcp-common.txt is created for tcp client
    
newclienttcp "$CLIENT"
	fi
	# Generates the custom client.ovpn
	
	
	
	echo ""
	echo "Finished!"
	echo ""
	echo "Your client config is available at ~/$CLIENT.ovpn"
	echo "If you want to add more clients, you simply need to run this script another time!"
fi