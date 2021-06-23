
#set -x
# ====================================================================================================
#
# Description: show.sh  - version 3.1 (works in conemu, cygwin, console2/console Z, xfce4-terminal)
#
# The script makes a list of all Cygwin servers in ~/.ssh/config and connects on selection
#
# call cygwin:
# mintty.exe -i /Cygwin-Terminal.ico -
#
#
# use cases:
    # show [-u username] [env] [grep-string1] [grep-string2]
    # show [-u user1|user2] [t1|t2|etc|qa|prod]  [...]
    # open terminal on selection
# use case 1
 # show.sh qa servers --> show qa servers & grep for "servers"
 # show.sh -u user1 etc servers --> show etc servers with user1@ & grep for "servers"
 # show.sh qa servers --> link "ss" (eg ss qa servers - starts a select menu with qa servers and grep for "servers")
# ====================================================================================================

usage ()
{
    echo 'The script makes a list of all local servers in ~/.ssh/config and connects on selection.'
    echo ''
    echo 'Usage: '
    echo '   - show [-u username] [env] [grep-string1] [grep-string2] '
    echo '   - show [-u user1|user2] [t1|t2|etc|qa|prod]  [...]'
    echo 'Keywords for advanced options: '
    echo '   - scp:         <source> [<destination>] (destination missing = download)'
    echo '   - remote:      <remote_command>   (executes a command remotely)'
    echo '   - custom[1-5]: <remote_command>   (save up to 5 remote commands for later use)'
    echo '   - list:                           (list the 5 saved remote commands)'
    echo '   - script: [sudo] <path/to/script> (executes a script remotely)'
    echo 'Example'
    echo '   - show.sh qa servers --> show qa servers & grep for "servers"'
    echo '   - show.sh -u user1 etc servers --> show etc servers with user1@ & grep for "servers"'
    echo '   - display usage: ./deployment_status.sh -h|--h|-help|--help'
    echo '   - show.sh -u user1 name_of_servers --> 1-3 remote: ls -ltrh'
    echo ''
    exit 0
}

# expand "1-3 4 5-6 " into "1 2 3 4 5 6" for example
number_expansion3 () {
    echo "$@" | awk 'BEGIN{ORS=" "} { for( i = 1; i <= NF; i++ ) {if($i ~/-/) { split($i,arr1,"-"); for( j = arr1[1]; j <= arr1[2]; j++) print j; } else print $i } }'
}


# default vars
env_string=""
env_string2=""
custom_grep=""
custom_grep2=""
ssh_user="user2"
opt=0
connection_count=0
sleep_time=15

function sleep_time_to_avoid_reset {
  if [[ $1 ]]; then
    sleep_time=$1
  fi

  if [ $connection_count -eq 18 ]; then
    echo "*** sleep $sleep_time seconds to avoid connection reset.."
    sleep $sleep_time
    #connection_count=0
  fi
}



# parameters
if [ $# -gt 0 ]; then
  for app in "$@"
    do
        # note that options like -u or -c should be given first
        case "$1" in
             e|etc)  env_string="ericsson-";  shift  ;;
             t1|test1)  env_string="vcc-test-"; env_string2="test-cn";  shift  ;;
             t2|test2)  env_string="vcc-test2-";  shift  ;;
             qa)  env_string="qa"; env_string2="q-";  shift  ;;
             prod)  env_string="p-"; env_string2="ap-";  shift  ;;
             -h|--h|-help|--help) usage;;
             -u|-user) ssh_user=$2 ; shift;  shift ;;
             -d|-user1) ssh_user="user1" ;  shift ;;
             -r|-root) ssh_user="root" ;  shift ;;
        esac

    done

    if [ $1 ]; then
    custom_grep=$1;
    shift;
    fi
    if [ $1 ]; then
    custom_grep2=$1;
    shift;
    fi
fi

# echo *debug* CONNECT_MODE $CONNECT_MODE . env_string $env_string . env_string2 $env_string2 . ssh_user $ssh_user . custom_grep $custom_grep . custom_grep2 $custom_grep2

# in case there is no env_string2
if [ "$env_string2" == "" ]; then
    env_string2="$env_string"
fi

ARR_HOSTS=($(egrep  "^Host $env_string.*|^Host $env_string2.*" ~/.ssh/config | sed "s/Host /ssh $ssh_user@/g" | awk '{print $2}' | grep .$custom_grep | grep .$custom_grep2) )
#ARR_HOSTS+=('Command')
#ARR_HOSTS=("Exit" "${ARR_HOSTS1[@]}")

PS3=" Select server: "

select dummy in "${choices[@]}"; do  # present numbered choices to user
  # Parse ,-separated numbers entered into an array.
  # Variable $REPLY contains whatever the user entered.
  IFS=', ' read -ra selChoices <<<"$REPLY"
  # Loop over all numbers entered.
  for choice in "${selChoices[@]}"; do
    # Validate the number entered.
    #(( choice >= 1 && choice <= ${#choices[@]} )) || { echo "Invalid choice: $choice. Try again." >&2; continue 2; }
    # If valid, echo the choice and its number.
    echo "Choice #$(( ++i )): ${choices[choice-1]} ($choice)"
  done
  # All choices are valid, exit the prompt.
  #break
done


select dummy in ${ARR_HOSTS[@]}; do
    printf "\n"

    # custom stuff
    is_remote_command=$(echo "$REPLY" | grep -ci 'remote:')
    is_remote_command_special=$(echo "$REPLY" | grep -ci 'remote::')
    is_scp_command=$(echo "$REPLY" | grep -ci 'scp:')
    is_scp_command_special=$(echo "$REPLY" | grep -ci 'scp::')
    is_remote_script=$(echo "$REPLY" | grep -ci 'script:')
    is_command_custom1=$(echo "$REPLY" | egrep -ci 'c1:|custom1:')
    is_command_custom2=$(echo "$REPLY" | egrep -ci 'c2:|custom2:')
    is_command_custom3=$(echo "$REPLY" | egrep -ci 'c3:|custom3:')
    is_command_custom4=$(echo "$REPLY" | egrep -ci 'c4:|custom4:')
    is_command_custom5=$(echo "$REPLY" | egrep -ci 'c5:|custom5:')
    is_custom_list=$(echo "$REPLY" | grep -ci 'list:')
    is_custom_list_ip=$(echo "$REPLY" | grep -ci 'listip:')

    remote_command=''
    scp_type=''
    scp_source=''
    scp_destination=''
    remote_enabled='no'
    remote_command_background_char=""


    if [ $is_remote_command -eq 1 ]; then

        remote_enabled='yes'
        if [ $is_remote_command_special -eq 1 ]; then
            remote_command=$(echo "$REPLY" | awk -F'remote::' '{print $2}')
            remote_command_background_char="&"
        else
            remote_command=$(echo "$REPLY" | awk -F'remote:' '{print $2}')
        fi
        REPLY=$(echo "$REPLY" | awk -F'remote:' '{print $1}')
        #echo "REPLY: $REPLY"
        echo "remote_command: $remote_command"
    fi

    if [ $is_scp_command -eq 1 ]; then
        remote_enabled='yes'
        if [ $is_scp_command_special -eq 1 ]; then
            scp_info=$(echo "$REPLY" | awk -F'scp::' '{print $2}')
            remote_command_background_char="&"
        else
            scp_info=$(echo "$REPLY" | awk -F'scp:' '{print $2}')
        fi
        #echo "REPLY: $REPLY scp_info: $scp_info"
        REPLY=$(echo "$REPLY" | awk -F'scp:' '{print $1}')
        scp_source=$(echo "$scp_info" | awk '{print $1}')
        scp_destination=$(echo "$scp_info" | awk '{print $2}')
        if [ -z "$scp_destination" ]; then
            scp_type='get'
        fi
        echo "scp_source: $scp_source"
        echo "scp_destination: $scp_destination"
    fi

    #custom1
    if [ $is_command_custom1 -eq 1 ]; then
        remote_enabled='yes'
        remote_command=$(echo "$REPLY" | awk -F'custom1:|c1:' '{print $2}')
        if [ -z "$remote_command" ]; then
          remote_command=$(cat $HOME/.custom1 2>/dev/null)
        else
          echo "Saving custom command in $HOME/.custom1 .."
          echo "$remote_command" > $HOME/.custom1
        fi
        REPLY=$(echo "$REPLY" | awk -F'custom1:|c1:' '{print $1}')
        #echo "REPLY: $REPLY"
        echo "remote_command_custom1: $remote_command"
        is_remote_command=1
    fi
    #custom2
    if [ $is_command_custom2 -eq 1 ]; then
        remote_enabled='yes'
        remote_command=$(echo "$REPLY" | awk -F'custom2:|c2:' '{print $2}')
        if [ -z "$remote_command" ]; then
          remote_command=$(cat $HOME/.custom2 2>/dev/null)
        else
          echo "Saving custom command in $HOME/.custom2 .."
          echo "$remote_command" > $HOME/.custom2
        fi
        REPLY=$(echo "$REPLY" | awk -F'custom2:|c2:' '{print $1}')
        #echo "REPLY: $REPLY"
        echo "remote_command_custom2: $remote_command"
        is_remote_command=1
    fi
    #custom3
    if [ $is_command_custom3 -eq 1 ]; then
        remote_enabled='yes'
        remote_command=$(echo "$REPLY" | awk -F'custom3:|c3:' '{print $2}')
        if [ -z "$remote_command" ]; then
          remote_command=$(cat $HOME/.custom3 2>/dev/null)
        else
          echo "Saving custom command in $HOME/.custom3 .."
          echo "$remote_command" > $HOME/.custom3
        fi
        REPLY=$(echo "$REPLY" | awk -F'custom3:|c3:' '{print $1}')
        #echo "REPLY: $REPLY"
        echo "remote_command_custom3: $remote_command"
        is_remote_command=1
    fi
    #custom4
    if [ $is_command_custom4 -eq 1 ]; then
        remote_enabled='yes'
        remote_command=$(echo "$REPLY" | awk -F'custom4:|c4:' '{print $2}')
        if [ -z "$remote_command" ]; then
          remote_command=$(cat $HOME/.custom4 2>/dev/null)
        else
          echo "Saving custom command in $HOME/.custom4 .."
          echo "$remote_command" > $HOME/.custom4
        fi
        REPLY=$(echo "$REPLY" | awk -F'custom4:|c4:' '{print $1}')
        #echo "REPLY: $REPLY"
        echo "remote_command_custom4: $remote_command"
        is_remote_command=1
    fi
    #custom5
    if [ $is_command_custom5 -eq 1 ]; then
        remote_enabled='yes'
        remote_command=$(echo "$REPLY" | awk -F'custom5:|c5:' '{print $2}')
        if [ -z "$remote_command" ]; then
          remote_command=$(cat $HOME/.custom5 2>/dev/null)
        else
          echo "Saving custom command in $HOME/.custom5 .."
          echo "$remote_command" > $HOME/.custom5
        fi
        REPLY=$(echo "$REPLY" | awk -F'custom5:|c5:' '{print $1}')
        #echo "REPLY: $REPLY"
        echo "remote_command_custom5: $remote_command"
        is_remote_command=1
    fi

    # the remote script
    if [ $is_remote_script -eq 1 ]; then
      printf "*** Executing script: \n\n"
      local_script_path=$(echo "$REPLY" | awk -F'script:' '{print $2}')

      remote_enabled='yes'

      # for executing script with sudo
      sudo=''
      scp_info=$(echo "$REPLY" | awk -F'script:' '{print $2}')
      if [[ "$scp_info" =~ "sudo" ]]; then
        echo Executing script with sudo.
        scp_info=$(echo "$scp_info" | sed 's/sudo//g')
        sudo='sudo'
      fi

      #echo "REPLY: $REPLY scp_info: $scp_info"
      REPLY=$(echo "$REPLY" | awk -F'script:' '{print $1}')
      scp_source=$(echo "$scp_info" | awk '{print $1}')
      scp_destination=$(echo "$scp_info" | awk '{print $2}')
      script_file_name=$(basename $scp_source)

      if [[ ! -f "$scp_source" ]]; then
        echo "Script not found: $scp_source"
        exit
      fi

      if [ "$scp_destination" ]; then
        script_path="$scp_destination"
      else
        script_path="/tmp"
        scp_destination="/tmp"
      fi

      # add self-delete to remote script:
      mkdir -p /tmp/showremotescriptwithselfremove/
      cp $scp_source /tmp/showremotescriptwithselfremove/
      scp_source=/tmp/showremotescriptwithselfremove/$script_file_name
      echo "cd $scp_destination" >> $scp_source
      echo 'rm -- "$0"' >> $scp_source

      echo "Script local source: $scp_source"
      echo "Script remote destination: $scp_destination"

      # remote command to execute script
      remote_command="$sudo chmod +x $script_path/$script_file_name ; cd $script_path ; $sudo ./$script_file_name"
      #echo "remote_command_script: $remote_command"
      is_remote_command=1
      is_scp_command=1
    fi

    if [ $is_custom_list -eq 1 ]; then
      printf "*** Remote command custom configuration list: \n\n"
      printf "$HOME/.custom1 - " ; cat $HOME/.custom1 2>/dev/null ; printf "\n"
      printf "$HOME/.custom2 - " ; cat $HOME/.custom2 2>/dev/null ; printf "\n"
      printf "$HOME/.custom3 - " ; cat $HOME/.custom3 2>/dev/null ; printf "\n"
      printf "$HOME/.custom4 - " ; cat $HOME/.custom4 2>/dev/null ; printf "\n"
      printf "$HOME/.custom5 - " ; cat $HOME/.custom5 2>/dev/null ; printf "\n"
      # workaround to avoid error on choice validation
      REPLY=$(echo "$REPLY" | sed 's/://g')
      #exit
    fi

    if [ $is_custom_list_ip -eq 1 ]; then
      # workaround to avoid error on choice validation
      REPLY=$(echo "$REPLY" | sed 's/listip://g')
      #exit
    fi


    REPLY=$(number_expansion3 "$REPLY")
    # Variable $REPLY contains whatever the user entered.
    IFS=', ' read -ra selChoices <<<"$REPLY"

    # Loop over all numbers entered.
    for choice in "${selChoices[@]}"; do
        # Validate the number entered.
        (( choice >= 1 && choice <= ${#ARR_HOSTS[@]} )) || { echo "Choice not in server list: $choice. Try again." >&2; continue 2; }
        sel="${ARR_HOSTS[choice-1]}"

        # case $sel in
         # Exit)
                # exit
            # ;;
         # Command)
                # ExecuteRemoteCommand
                # remote_command=$(echo $sel | awk '{print NF}');
                # remote_command=$(echo $sel | awk '{print NF}');
                # echo executing
            # ;;
        # esac

        # list the IP and HostName for selection
        if [ $is_custom_list_ip -eq 1 ]; then
          configuredhost=$(echo $sel | awk -F'@' '{print $2}')
          grep -v \# ~/.ssh/config | awk 'BEGIN{prevhost="no"; mystring=""} /^Host|ProxyCommand/{if ($1 ~/Host/) { if ($prevhost == "yes"){ ORS="\n" } else ORS=" ||"; mystring=$0" "; prevhost = "yes"} else {prevhost = "no"; ORS="\n" ; print $5 "\t" mystring } }' | sed 's/ \+/ /g;s/:%p//g;s/Host //g' | grep $configuredhost
          continue
        fi

        echo -e "\e[1;36m\nConnecting to ($choice) $sel .. \e[0m"
        #mintty.exe -i /Cygwin-Terminal.ico ssh $sel &
        #ConEmuC -c bash -new_console -c "ssh $sel" &
        if ! type "ConEmuC64" > /dev/null 2>&1; then
            if type "console.exe" > /dev/null 2>&1; then
                # you are probably in console2 or consoleZ
                server=`echo $sel | awk -F "@" '{print $2}'`
                if [ "$remote_enabled" == "no" ]; then
                    console.exe -t bash3 -n $server -reuse -r "-c 'ssh $sel'" &
                fi
            else
                if type "mintty.exe" > /dev/null 2>&1; then
                    # you are probably in cygwin
                    if [ "$remote_enabled" == "no" ]; then
                        mintty.exe -i /Cygwin-Terminal.ico ssh $sel &
                    fi
                else
                    # echo "[Info] if you see this you dont have mintty.exe, ConEmuC64 or console.exe in PATH."
                    if [ "$remote_enabled" == "no" ]; then
                      xfce4-terminal --tab -e "ssh $sel" &
                      # normal ssh
                      #ssh $sel
                      # terminator shell
                      #terminator  --new-tab --command="ssh $sel" 2>/dev/null &
                    fi
                fi
            fi
        else
            # you are probably in ConEmu
            server=`echo $sel | awk -F "@" '{print $2}'`
            #echo $server
            #ConEmuC64 -c bash -new_console:t:"$server" -c "ssh $sel" &
            if [ "$remote_enabled" == "no" ]; then
                ConEmuC64 -c bash -new_console:C:"%ConEmuDrive%\cygwin64\Cygwin.ico" -new_console:t:"$server" -c "ssh $sel" &
            fi
        fi

        if [ $is_scp_command -eq 1 ]; then
          let connection_count=connection_count+1
          sleep_time_to_avoid_reset 15

          if [ "$scp_type" == "get" ]; then
              scp $sel:$scp_source .
          else
              # alternative with eval
              if [ $is_scp_command_special -eq 1 ]; then
                  scp $scp_source $sel:$scp_destination &
              else
                  scp $scp_source $sel:$scp_destination
              fi
          fi

        fi

        if [ $is_remote_command -eq 1 ]; then
            let connection_count=connection_count+1
            sleep_time_to_avoid_reset 25

            if [ $is_remote_command_special -eq 1 ]; then
                ssh -qt $sel $remote_command $remote_command_background_char
            else
                ssh -qt $sel $remote_command
            fi

        fi

    done
    exit
done

