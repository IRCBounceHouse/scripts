#Random generator ipv6 addresses within your ipv6 network prefix.
#!/bin/bash

array=( 1 2 3 4 5 6 7 8 9 0 a b c d e f )
count=1
network=2607:fe90:4:b:5054 # your ipv6 network prefix

rnd_ip_block (){
    a=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    b=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    c=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    d=${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}${array[$RANDOM%16]}
    # Since $network already has 5 groups, we only need 3 more to make a full v6 address, so we don't use $d
    echo $network:$a:$b:$c
}

set_MAXCOUNT (){
  read -p "Enter an amount of IPv6 addresses to generate: " addamount
  MAXCOUNT=$addamount
  generate
}

generate () {
  echo "$MAXCOUNT random IPv6:"
  echo "-----------------"
  while [ "$count" -le $MAXCOUNT ]
  do
        rnd_ip_block
        let "count += 1"
        done
  echo "-----------------"
}

if [ -n "$1" ]; then
    MAXCOUNT=$1
    generate
  else set_MAXCOUNT
fi
