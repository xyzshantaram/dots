function __prompt_time --description 'Show clock in [HH:MM:SS:MS]'
    # Fish lacks nanosecond formatting; use millisecond approximation
    set -l now (date "+%H:%M:%S")
    set -l ms (date "+%3N")
    set_color grey
    echo -n "[$now:$ms]"
    set_color normal
end

function __prompt_userhost --description 'Username@hostname, colorized'
    set_color -o magenta
    echo -n (whoami)
    set_color green
    echo -n @
    # `hostname` is not installed on this system, so ask systemd instead.
    echo -n (hostnamectl hostname)
    set_color normal
end

function __prompt_directory --description 'Current directory, folder icon'
    set_color white
    echo -n "  "(prompt_pwd)
    set_color normal
end

function __prompt_venv --description "Show venv if present"
    if set -q VIRTUAL_ENV
        set_color yellow
        echo -n "( "(basename $VIRTUAL_ENV)")"
        set_color normal
        echo -n " "
    end
end

function __prompt_cmd_status --description "Show command status [ready]/[ERR]"
    if test $argv[1] -eq 0
        set_color brgreen
        echo -n "[ready]"
    else
        set_color red
        echo -n "[$argv[1]]"
    end
    set_color normal
end

function __prompt_git --description 'Compact, colorized git branch/status summary using ANSI codes'
    set -l prompt (string trim (fish_git_prompt))
    if test -n "$prompt"
        echo -ne "$prompt "
    end
end

function fish_prompt
    set -l last_status $status
    # Icons: '' is the Arch logo, and needs a Nerd Font to render. This ladder
    # installs Lilex Nerd Font Mono (see 40-packages.ts and 80-fonts.ts).
    # First line: time, user/host, folder, git, venv
    set_color blue
    echo -n ' '
    set_color normal
    __prompt_time
    echo -n " "
    __prompt_userhost
    echo -n " "
    __prompt_directory
    echo -n " "
    __prompt_venv
    echo

    # Second line: Command status / prompt char
    __prompt_git
    __prompt_cmd_status $last_status
    echo -n " "
end
