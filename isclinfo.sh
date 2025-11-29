#!/usr/bin/env bash

INCLUDE_SYSTEM_PHP=true
PANEL="Unknown"

php_bins=()

if [[ -d /usr/local/directadmin ]]; then
  PANEL="DirectAdmin"
  for bin in /usr/local/php*/bin/php; do
    [[ -x "$bin" ]] && php_bins+=("$bin")
  done
elif [[ -d /opt/cpanel ]]; then
  PANEL="cPanel"
  for bin in /opt/cpanel/ea-php*/root/usr/bin/php; do
    [[ -x "$bin" ]] && php_bins+=("$bin")
  done
fi

if [[ "$INCLUDE_SYSTEM_PHP" == true && -x "$(command -v php)" ]]; then
  php_bins+=("$(command -v php)")
fi

if ((${#php_bins[@]} == 0)); then
  echo "No PHP binaries found."
  exit 1
fi

php_bins=($(printf "%s\n" "${php_bins[@]}" | awk '!seen[$0]++'))

HELPER="/tmp/php_env_inspector_helper.php"

cat <<'PHP' > "$HELPER"
#!/usr/bin/env php
<?php
function color($t,$c){return "\033[".$c."m".$t."\033[0m";}
$section=$argv[1]??'all';

$activeModules=get_loaded_extensions();
sort($activeModules);

$allKnownModules=[
"bcmath","bz2","calendar","Core","ctype","curl","date","dba","dom","exif","FFI",
"fileinfo","filter","ftp","gd","gettext","gmp","hash","iconv","imap","intl","json",
"ldap","libxml","mbstring","mysqli","mysqlnd","odbc","openssl","pcntl","pcre","PDO",
"pdo_mysql","pdo_pgsql","pdo_sqlite","pdo_odbc","Phar","posix","readline","Reflection",
"session","shmop","SimpleXML","snmp","soap","sockets","sodium","sqlite3","standard",
"sysvmsg","sysvsem","sysvshm","tokenizer","xml","xmlreader","xmlwriter","xsl",
"Zend OPcache","zip","zlib","imagick","ionCube Loader","apcu","redis","memcached"
];
sort($allKnownModules);

$inactiveModules=array_diff($allKnownModules,$activeModules);

$phpVersion=phpversion();
$server=$_SERVER['SERVER_SOFTWARE']??'Unknown (CLI or not set)';
$os=php_uname();
$memoryLimit=ini_get('memory_limit');
$uploadMax=ini_get('upload_max_filesize');
$postMax=ini_get('post_max_size');
$maxExecTime=ini_get('max_execution_time');
$maxInputVars=ini_get('max_input_vars');
$displayErr=ini_get('display_errors')?'On':'Off';
$allowUrlFopen=ini_get('allow_url_fopen')?'On':'Off';
$phpIniPath=php_ini_loaded_file()?:'Unknown';
$zendVersion=zend_version();

$dangerousFuncs=[
"shell_exec","system","passthru","exec","popen","ini_restore","socket_create",
"socket_create_listen","socket_create_pair","socket_listen","socket_bind","symlink",
"link","pfsockopen","ini_alter","dl","pcntl_exec","pcntl_fork","proc_close",
"proc_open","proc_terminate","posix_kill","posix_mkfifo","posix_setpgid",
"posix_setsid","posix_setuid","posix_setgid","posix_uname","show_source",
"getfile","mkfifo"
];

$disabledFuncs=ini_get('disable_functions');
$disabledFuncs=$disabledFuncs?array_map('trim',explode(',',$disabledFuncs)):[];
$reallyDisabled=array_intersect($dangerousFuncs,$disabledFuncs);

$sourceGuardianStatus=extension_loaded('SourceGuardian')?'Enabled':'Disabled';
$ioncubeStatus=extension_loaded('ionCube Loader')?'Enabled':'Disabled';
$sourceGuardianVersion=$sourceGuardianStatus==='Enabled'&&phpversion('SourceGuardian')?phpversion('SourceGuardian'):'-';
$ioncubeVersion=$ioncubeStatus==='Enabled'&&function_exists('ioncube_loader_version')?ioncube_loader_version():'-';

function print_general($phpVersion,$zendVersion,$server,$os,$phpIniPath,$memoryLimit,$uploadMax,$postMax,$maxExecTime,$maxInputVars,$displayErr,$allowUrlFopen){
  echo color("General Info","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "PHP Version        : $phpVersion\n";
  echo "Zend Engine        : $zendVersion\n";
  echo "Server Software    : $server\n";
  echo "Operating System   : $os\n";
  echo "Loaded php.ini     : $phpIniPath\n";
  echo "memory_limit       : $memoryLimit\n";
  echo "upload_max_filesize: $uploadMax\n";
  echo "post_max_size      : $postMax\n";
  echo "max_execution_time : $maxExecTime seconds\n";
  echo "max_input_vars     : ".($maxInputVars?:'not set')."\n";
  echo "display_errors     : $displayErr\n";
  echo "allow_url_fopen    : $allowUrlFopen\n";
  echo str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function print_sg($sourceGuardianStatus,$sourceGuardianVersion,$ioncubeStatus,$ioncubeVersion){
  echo color("SourceGuardian / ionCube","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "SourceGuardian:\n";
  echo "  Status : $sourceGuardianStatus\n";
  echo "  Version: $sourceGuardianVersion\n\n";
  echo "ionCube Loader:\n";
  echo "  Status : $ioncubeStatus\n";
  echo "  Version: $ioncubeVersion\n";
  echo str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function print_active($activeModules){
  echo color("Active Extensions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "Active extensions (".count($activeModules)."):\n";
  echo $activeModules?implode(", ",$activeModules):"(none)";
  echo PHP_EOL.str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function print_inactive($inactiveModules){
  echo color("Inactive Known Extensions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  echo "Inactive known extensions (".count($inactiveModules)."):\n";
  echo $inactiveModules?implode(", ",$inactiveModules):"(none or not detectable)";
  echo PHP_EOL.str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function print_danger($reallyDisabled){
  echo color("Disabled Dangerous Functions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  if($reallyDisabled){
    echo "These high-risk functions are disabled:\n";
    echo implode(", ",$reallyDisabled).PHP_EOL;
  } else {
    echo "No dangerous functions disabled (or disable_functions is empty).\n";
  }
  echo str_repeat("-",60).PHP_EOL.PHP_EOL;
}

function print_raw($disabledFuncs){
  echo color("Raw disable_functions","1;34").PHP_EOL;
  echo str_repeat("-",60).PHP_EOL;
  if($disabledFuncs){
    echo "disable_functions list:\n";
    echo implode(", ",$disabledFuncs).PHP_EOL;
  } else {
    echo "(disable_functions is empty)\n";
  }
  echo str_repeat("-",60).PHP_EOL.PHP_EOL;
}

switch($section){
  case 'general':
    print_general($phpVersion,$zendVersion,$server,$os,$phpIniPath,$memoryLimit,$uploadMax,$postMax,$maxExecTime,$maxInputVars,$displayErr,$allowUrlFopen);
    break;
  case 'sg':
    print_sg($sourceGuardianStatus,$sourceGuardianVersion,$ioncubeStatus,$ioncubeVersion);
    break;
  case 'active':
    print_active($activeModules);
    break;
  case 'inactive':
    print_inactive($inactiveModules);
    break;
  case 'danger':
    print_danger($reallyDisabled);
    break;
  case 'raw':
    print_raw($disabledFuncs);
    break;
  case 'all':
  default:
    print_general($phpVersion,$zendVersion,$server,$os,$phpIniPath,$memoryLimit,$uploadMax,$postMax,$maxExecTime,$maxInputVars,$displayErr,$allowUrlFopen);
    print_sg($sourceGuardianStatus,$sourceGuardianVersion,$ioncubeStatus,$ioncubeVersion);
    print_active($activeModules);
    print_inactive($inactiveModules);
    print_danger($reallyDisabled);
    print_raw($disabledFuncs);
    break;
}
PHP

chmod +x "$HELPER"

selected_php=""

while true; do
  if [[ -z "$selected_php" ]]; then
    clear
    echo "Control panel detected: $PANEL"
    echo
    echo "Detected PHP binaries:"
    echo "----------------------"
    i=1
    for bin in "${php_bins[@]}"; do
      ver="$("$bin" -v 2>/dev/null | head -n1)"
      [[ -z "$ver" ]] && ver="(version unknown)"
      printf " [%d] %s\n     %s\n\n" "$i" "$ver" "$bin"
      ((i++))
    done

    read -rp "Select the PHP version number to use (or 0 to quit): " choice

    if [[ "$choice" == "0" ]]; then
      clear
      echo "Bye."
      exit 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#php_bins[@]} )); then
      echo "Invalid choice."
      sleep 1
      continue
    fi

    selected_php="${php_bins[$((choice-1))]}"
    clear
    echo "Control panel detected: $PANEL"
    echo "Using PHP binary: $selected_php"
    echo
  fi

  echo "================ PHP Environment Inspector ================"
  echo "Control panel: $PANEL"
  echo "Using: $selected_php"
  echo
  echo "Select a section to view:"
  echo "  1) General Info"
  echo "  2) SourceGuardian / ionCube"
  echo "  3) Active Extensions"
  echo "  4) Inactive Known Extensions"
  echo "  5) Disabled Dangerous Functions"
  echo "  6) Raw disable_functions"
  echo "  7) Show ALL sections"
  echo "  9) Change PHP version"
  echo "  0) Quit"
  echo "--------------------------------------------------------"
  read -rp "Enter choice: " sec

  case "$sec" in
    0|q|Q)
      clear
      echo "Bye."
      exit 0
      ;;
    9)
      selected_php=""
      clear
      continue
      ;;
    1) SECTION="general" ;;
    2) SECTION="sg" ;;
    3) SECTION="active" ;;
    4) SECTION="inactive" ;;
    5) SECTION="danger" ;;
    6) SECTION="raw" ;;
    7) SECTION="all" ;;
    *)
      clear
      echo "Invalid choice."
      echo
      continue
      ;;
  esac

  clear
  echo "Control panel: $PANEL"
  echo "Using: $selected_php"
  echo
  echo "=== Section: $SECTION ==="
  echo

  "$selected_php" "$HELPER" "$SECTION"

  echo
  read -rp "Press Enter to go back to menu..." _
  clear
done
