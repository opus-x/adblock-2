#!/bin/bash

# DO NOT MODIFY THIS FILE. MODIFY SETTINGS VIA THE CONFIGURATION FILES IN
# /opt/etc/hostsblock/

eval PATH=/opt/usr/sbin:/opt/etc/init.d:$PATH

# CHECK FOR NEEDED AND OPTIONAL UTILITIES AND PERMISSIONS
if [ `whoami` != "root" ]; then
    echo "Insufficient permissions. Run as root."
    exit 1
fi

for dep in curl grep sed tr cut; do
    if which "$dep" &>/dev/null; then
        true
    else
        if [ "$dep" == "tr" ]; then
            echo "coreutils is not installed or not in your PATH. Please remedy. Exiting."
        else
            echo "Utility $dep not installed or not in your PATH. Please remedy. Exiting."
        fi
        exit 1
    fi
done

if which unzip &>/dev/null; then
    zip="1"
else
    echo "Dearchiver unzip not found. URLs which use this format will be skipped."
    zip="0"
fi
if which 7za &>/dev/null; then
    zip7="1"
else
    echo "Dearchiver 7za not found. URLs which use this format will be skipped."
    zip7="0"
fi

# DEFAULT SETTINGS
tmpdir="/tmp"
hostsfile="/opt/etc/hosts.block"
redirecturl="127.0.0.1"
postprocess(){
    service dnsmasq restart
    /opt/etc/init.d/S60pixelserv restart
}
blocklists="http://support.it-mate.co.uk/downloads/HOSTS.txt"
logfile="/opt/var/log/hostsblock.log"
blacklist="/opt/etc/hostsblock/black.list"
whitelist="/opt/etc/hostsblock/white.list"
hostshead="0"
cachedir="/opt/var/cache/hostsblock"
redirects="0"

# CHECK TO SEE IF WE ARE LOGGING THIS
if [ "$logfile" != "0" ]; then
    exec > "$logfile" 2>&1
fi

echo -e "\nHostsblock started at `date +'%x %T'`"

# READ CONFIGURATION FILE.
if [ -f /opt/etc/hostsblock/hostsblock.conf ]; then
    . /opt/etc/hostsblock/hostsblock.conf
else
    echo "Config file /opt/etc/hostsblock/hostsblock.conf not found. Using defaults."
fi

# CREATE CACHE DIRECTORY IF NOT ALREADY EXISTANT
[ -d "$cachedir" ] || mkdir -p "$cachedir"

# DOWNLOAD BLOCKLISTS
changed=0
echo -e "\nChecking blocklists for updates..."

if [ -f /opt/etc/hostsblock/blocklists.csv ]; then
    OLD_IFS=$IFS
    IFS=','
    while read switch url ; do
        if [ "$switch" == "1" ]; then
            printf "   `echo $url | tr -d '%'`..."
            outfile=`echo $url | sed 's|http:\/\/||g' | tr '/%&+?=' '.'`
            [ -f "$cachedir"/"$outfile" ] && old_ls=`ls -l "$cachedir"/"$outfile"`
            if curl --compressed --connect-timeout 60 -sz "$cachedir"/"$outfile" "$url" -o "$cachedir"/"$outfile"; then
                new_ls=`ls -l "$cachedir"/"$outfile"`
                if [ "$old_ls" != "$new_ls" ]; then
                    changed=1
            printf "UPDATED"
        else
            printf "no changes"
        fi
    else
        printf "FAILED\nScript exiting @ `date +'%x %T'`"
        exit 1
    fi
        else
            continue
        fi
    done < /opt/etc/hostsblock/blocklists.csv
    IFS=$OLD_IFS
else
    echo "Config file /opt/etc/hostsblock/blocklists.csv not found."
fi

# IF THERE ARE CHANGES...
if [ "$changed" != "0" ]; then
    echo -e "\nDONE. Changes found."

    # CREATE TMPDIR
    [ -d "$tmpdir"/hostsblock/hosts.block.d ] || mkdir -p "$tmpdir"/hostsblock/hosts.block.d

    # BACK UP EXISTING HOSTSFILE
    printf "\nBacking up $hostsfile to $hostsfile.old..."
    cp "$hostsfile" "$hostsfile".old && printf "done" || printf "FAILED"

    # EXTRACT CACHED FILES TO HOSTS.BLOCK.D
    printf "\n\nExtracting and preparing cached files to working directory..."
    n=1
    if [ -f /opt/etc/hostsblock/blocklists.csv ]; then
        OLD_IFS=$IFS
        IFS=','
        while read switch url ; do
            if [ "$switch" == "1" ]; then
        FILE=`echo $url | sed "s|http:\/\/||g" | tr '/%&=?' '.'`
        printf "\n    `basename $FILE | tr -d '\%'`..."
        case "$FILE" in
            *".zip")
                if [ $zip == "1" ]; then
                    mkdir "$tmpdir"/hostsblock/tmp
                    cp "$cachedir"/"$FILE" "$tmpdir"/hostsblock/tmp
                    cd "$tmpdir"/hostsblock/tmp
                    printf "extracting..."
                    unzip -jq "$FILE" &>/dev/null && printf "extracted..." || printf "FAILED"
                    grep -rIh -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" ./* > "$tmpdir"/hostsblock/hosts.block.d/hosts.block.$n
                    cd "$tmpdir"/hostsblock
                    rm -r "$tmpdir"/hostsblock/tmp
                    printf "prepared"
                else
                    printf "unzip not found. Skipping"
                fi
            ;;
            *".7z")
                if [ $zip7 == "1" ]; then
                    mkdir "$tmpdir"/hostsblock/tmp
                    cp "$cachedir"/"$FILE" "$tmpdir"/hostsblock/tmp
                    cd "$tmpdir"/hostsblock/tmp
                    printf "extracting..."
                    7za e "$FILE" &>/dev/null && printf "extracted..." || printf "FAILED"
                    grep -rIh -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" ./* > "$tmpdir"/hostsblock/hosts.block.d/hosts.block.$n
                    cd "$tmpdir"/hostsblock
                    rm -r "$tmpdir"/hostsblock/tmp
                    printf "prepared"
                else
                    printf "7za not found. Skipping"
                fi
            ;;
            *)
                cp "$cachedir"/"$FILE" "$tmpdir"/hostsblock/hosts.block.d/hosts.block.$n && printf "prepared" || printf "FAILED"
            ;;
        esac
        let "n+=1"
            else
                continue
            fi
        done < /opt/etc/hostsblock/blocklists.csv
        IFS=$OLD_IFS
    else
        echo "Config file /opt/etc/hostsblock/blocklists.csv not found."
    fi

    # INCLUDE LOCAL BLACKLIST FILE
    echo -e "\n    Local blacklist..."
    cat "$blacklist" |\
    sed "s|^|$redirecturl |g" >> "$tmpdir"/hostsblock/hosts.block.d/hosts.block.0 && echo "prepared" || echo "FAILED"

    # GENERATE WHITELIST SED SCRIPT
    printf "\n    Local whitelist..."
    cat "$whitelist" |\
    sed -e 's/.*/\/&\/d/' -e 's/\./\\./g' >> "$tmpdir"/hostsblock/whitelist.sed && printf "prepared" || printf "FAILED"

    # DETERMINE THE REDIRECT URL NOT BEING USED
    if [ "$redirecturl" == "127.0.0.1" ]; then
        notredirect="0.0.0.0"
    else
        notredirect="127.0.0.1"
    fi

    # PROCESS BLOCKLIST ENTRIES INTO TARGET FILE
    if [ "$hostshead" == "0" ]; then
        rm "$hostsfile"
    else
        cp -f "$hostshead" "$hostsfile"
    fi

    printf "\nDONE.\n\nProcessing files..."
    # DETERMINE WHETHER TO INCLUDE REDIRECTIONS
    if [ "$redirects" == "1" ]; then
        grep_eval='grep -Ih -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" "$tmpdir"/hostsblock/hosts.block.d/*'
    else
        grep_eval='grep -IhE -- "^127\.0\.0\.1|^0\.0\.0\.0" "$tmpdir"/hostsblock/hosts.block.d/*'
    fi

    # PROCESS AND WRITE TO FILE
    eval $grep_eval | sed -e 's/[[:space:]][[:space:]]*/ /g' -e "s/\#.*//g" -e "s/[[:space:]]$//g" -e \
    "s/$notredirect/$redirecturl/g" | sort -u | sed -f "$tmpdir"/hostsblock/whitelist.sed >> "$hostsfile" && printf "done\n"

    # APPEND BLACKLIST ENTRIES
    printf "\nAppending blacklist entries..."
    cat "$blacklist" |\
        sed "s|^|$redirecturl |g" >> "$hostsfile" && printf "done\n" || printf "FAILED\n"

    # REPORT COUNT OF MODIFIED OR BLOCKED URLS
    for addr in `grep -Ih -- "^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}" "$hostsfile" | cut -d" " -f1 | sort -u |\
    tr '\n' ' '`; do
        number=`grep -c -- "^$addr" "$hostsfile"`
        if [ "$addr" == "$redirecturl" ]; then
            printf "\n$number urls blocked"
        else
            printf "\n$number urls redirected to $addr"
        fi
    done

    #Выбираем только нужные строки из чёрного списка
    sed -i -e '/^[0-9A-Za-z]/!d' "$hostsfile"
    sed -i -e '/%/d' "$hostsfile"
    sed -i -e 's/[[:cntrl:][:blank:]]//g' "$hostsfile"
    sed -i -e 's/^[ \t]*//;s/[ \t]*$//' "$hostsfile"

    # dnsmasq, чистим, оптимизируем
    sed -i -e 's/[[:space:]]*\[.*$//'  "$hostsfile"
    sed -i -e 's/[[:space:]]*\].*$//'  "$hostsfile"
    sed -i -e '/[[:space:]]*#.*$/ s/[[:space:]]*#.*$//'  "$hostsfile"
    sed -i -e '/^$/d' "$hostsfile"
    sed -i -e '/127.0.0.1/ s/127.0.0.1//'  "$hostsfile"
    sed -i -e '/192.168.1.2/ s/192.168.1.2//'  "$hostsfile"
    sed -i -e '/^www[0-9]./ s/^www[0-9].//'  "$hostsfile"
    sed -i -e '/^www./ s/^www.//' "$hostsfile"
    # удаляем дубликаты
    cat "$hostsfile" | sort -u > "$hostsfile".new
    mv "$hostsfile".new "$hostsfile"

    ## including important informations
    echo  "##" >>/tmp/adblock.conf
    echo  "##-----------------------------------------" >>/tmp/adblock.conf
    echo  "##    Generated by AdBlock script v2.0     " >>/tmp/adblock.conf
    echo  "##    Grabbed on $(date)" >>/tmp/adblock.conf
    echo  "##    "`cat "$hostsfile" | wc -l`" blocked hosts" >> /tmp/adblock.conf
    echo  "##-----------------------------------------" >>/tmp/adblock.conf
    echo  "##" >>/tmp/adblock.conf
    awk 'ORS=(NR%5)?"/":"/\n" ; BEGIN{end = 0} ; END{printf (NR%5)?"\n":""}' "$hostsfile" | sed "s_^_address=/_ ; s/$/$redirecturl/">>/tmp/adblock.conf
#    rm -rf "$hostsfile"

    # Replace the adblock stuff in the "custom" file.
    sed -i "/^#BEGIN--adblock-custom/,/^#END--adblock-custom/d" /tmp/etc/dnsmasq.custom
    echo -e "#BEGIN--adblock-custom\nconf-file=/opt/etc/adblock.conf\n#END--adblock-custom" > /tmp/etc/dnsmasq.custom

    mv /tmp/adblock.conf /opt/etc/adblock.conf

    # COMMANDS TO BE EXECUTED AFTER PROCESSING
    printf "\n\nRunning postprocessing..."
    postprocess && printf "done\n" || printf "FAILED"

    # CLEAN UP
    rm -r "$tmpdir"/hostsblock
else
    echo -e "\nDONE. No new changes."
fi
echo -e "\nHostsblock completed at `date +'%x %T'`\n"
