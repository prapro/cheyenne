REBOL [
	Title: "Cheyenne Web Server"
	Author: "SOFTINNOV / Nenad Rakocevic"
	Purpose: "Full-featured Web Server"
	Encap: [quiet secure none title "Cheyenne" no-window] 
	Version: 0.9.20
	Date: 08/03/2009
]

; === Setting up the runtime context ===

system/network/host: does [system/network/host: read dns://]
system/network/host-address: does [
	system/network/host-address: read join dns:// system/network/host
]

;--- Windows include paths ---
#if [system/version/4 = 3] [
	#include %//dev/REBOL/SDK/Source/mezz.r
	#include %//dev/REBOL/SDK/Source/prot.r
	#include %//dev/REBOL/SDK/Source/gfx-colors.r
]
;--- OS X include paths ---
#if [system/version/4 = 2] [
	#include %/Users/dk/dev/sdk/source/mezz.r
	#include %/Users/dk/dev/sdk/source/prot.r
	#include %/Users/dk/dev/sdk/source/gfx-colors.r
]
;--- Linux include paths ---
#if [system/version/4 = 4] [
	#include %/root/Desktop/sdk/source/mezz.r
	#include %/root/Desktop/sdk/source/prot.r
	#include %/root/Desktop/sdk/source/gfx-colors.r
]

uniserve-path: %../UniServe/
modules-path: %handlers/

#include %../UniServe/libs/encap-fs.r
unless value? 'encap-fs [do uniserve-path/libs/encap-fs.r]
#include %.cache.efs

set-cache [
	%HTTPd.r
	%httpd.cfg
	%misc/ [
		%conf-parser.r
		%debug-head.html
		%debug-menu.rsp
		%mime.types
		%system.r
		%os.r
		%service.dll
		%win32.r
		%unix.r
		%macosx.r
		%admin.r
	]
	%mods/ [
		%mod-action.r
		%mod-alias.r
		%mod-fastcgi.r
		%mod-rsp.r
		%mod-ssi.r
		%mod-static.r
		%mod-userdir.r
		%mod-internal.r
		%mod-extapp.r
	]
	%handlers/ [
		%CGI.r
		%RSP.r
	]
	%internal/ [
		%about.rsp
		%backgroundbottom.gif
		%backgroundmiddle.gif
		%backgroundtop.gif
		%bullet.gif
		%cheyenne.png
		%default.css
		%rebol.gif
		%si.png
	]
	uniserve-path [
		%uni-engine.r
		%libs/ [
			%headers.r
			%log.r
			%html.r
			%decode-cgi.r
			%idate.r
			%cookies.r
			%url.r
		]
		%services/ [
			%logger.r
			%RConsole.r
			%task-master.r
			%task-master/ [
				%task-handler.r
			]
		]
		%protocols/FastCGI.r
	]
]

do-cache uniserve-path/libs/log.r

; === Patched functions ====

set 'info? func [
    "Returns information about a file or url."
    [catch]
    target [file! url!]
][
    throw-on-error [
        target: make port! target
        query target
    ]
    either none? target/status [
        none
    ] [
        make object! [
            size: target/size 
            date: target/date
            type: any [
            	all [target/status = 'directory 'directory]
            	target/scheme
            ]
        ]
    ]
]

; === Applications launcher ===

cheyenne: make log-class [
	name: 'boot
	verbose: 1
	
	value: none
	data-dir: system/options/path
	
	sub-args: ""
	args: []
	flags: []
	set-flag: func [w][any [find flags w append flags w]]
	flag?: func [w][to logic! find flags w]
	flags?: func [b][equal? length? b length? intersect flags b]
	propagate: func [arg][append sub-args arg]
	
	set 'OS-Windows? system/version/4 = 3
	
	unless value? 'do-events [set 'do-events does [wait []]]
		
	within: func [obj [object! port!] body [block!]][
		do bind body in obj 'self
	]
	
	do-cheyenne-app: has [port-id verbosity service? home][	
		if flag? 'custom-port [port-id: args/port-id]
		if flag? 'verbose [verbosity: args/verbosity]
		
		do-cache uniserve-path/uni-engine.r

		either service?: all [OS-Windows? flag? 'service][
			launch-service				; -- launch service thread
			do-cache %misc/admin.r
		][
			do-cache %misc/system.r		; -- install tray icon for Windows
		]

		do-cache uniserve-path/services/task-master.r		
		do-cache uniserve-path/services/RConsole.r	
		do-cache uniserve-path/services/logger.r
		do-cache uniserve-path/protocols/FastCGI.r
		do-cache %HTTPd.r

		within uniserve [
			if port-id [	
				;-- translate Task-master's listen port to allow several instances to run
				services/task-master/port-id: ((port-id/1 + 2000) // 64512) + 1024
; TDB: should do the same for Logger and RConsole service !!
			]
			verbose: 						any [all [verbosity verbosity - 1] 0]
			services/httpd/verbose: 		any [verbosity 0]
			services/task-master/verbose: 	any [all [2 < any [verbosity 0] verbosity - 1] 0]
			shared/pool-start: 				any [all [flag? 'debug 1] all [flag? 'workers args/workers] 4]
			shared/pool-max: 				any [all [flag? 'debug 0] all [flag? 'workers args/workers] 8]
			shared/job-max: 				1000	;-- CGI/RSP requests queue size

			boot/with/no-wait/no-start [] ; empty block avoids loading modules from disk
			control/start/only 'RConsole none
			control/start/only 'Logger none
			if service? [control/start/only 'admin none]

			all [
				not port-id
				port-id: select services/httpd/conf/globals 'listen
				port-id: to-block port-id
			]
			
			if OS-Windows? [
				if not service? [
					set-tray-help-msg rejoin [
						"Cheyenne is listening on port: " mold any [port-id 80]
					]
				]
				open-system-events
			]
			
			foreach p any [port-id [80]][control/start/only 'HTTPd p]
			
			control/start/only 'task-master none
		]
		if flag? 'embed [exit]
		
		until [
			do-events
			unless uniserve/flag-stop [log/warn "premature exit from event loop"]
			uniserve/flag-stop
		]
		if verbose > 0 [log/info "exit from event loop"]
	]
	
	do-bg-process-app: does [
		do-cache uniserve-path/services/task-master/task-handler.r
		ctx-task-class/connect
	]
	
	do-tray-app: does [
		do-cache %misc/system.r
		set-tray-remote-events
		do-events
	]
	
	do-uninstall-app: does [
		if NT-service? [
			if NT-service-running? [control-service/stop]
			uninstall-NT-service
		]
	]
	
	set-working-folders: has [home][
		home: dirize first split-path system/options/boot
		change-dir system/options/home: system/options/path: home
		OS-change-dir home
		data-dir: either flag? 'folder [args/folder][home]
		if any [
			flag? 'user-desktop
			all [
				not flag? 'service
				data-dir = OS-get-dir 'desktop
			]
		][
			set-flag 'user-desktop
			data-dir: join OS-get-dir 'all-users %Cheyenne/
			make-dir/deep data-dir
		]
	]
		
	parse-cmd-line: has [ssa digit value][
		digit: charset [#"0" - #"9"]
		if ssa: system/script/args [
			parse ssa [
				any [
					"task-handler" (set-flag 'bg-process) break 
					| "-p" copy value any [1 5 digit opt #","] (
						repend args [
							'port-id
							to-block replace/all value "," " "
						]
						set-flag 'custom-port
					)
					| "-fromdesk" (set-flag 'user-desktop)	; -- internal use only
					| "-f" copy value [to " " | to end](
						set-flag 'folder 
						repend args ['folder load trim value]
						propagate reduce [" -f " value]
					)
					| "-e" 		(set-flag 'embed)
					| "-s" 		(set-flag 'service)			; -- internal use only
					| "-u"		(set-flag 'uninstall)				
					| "-w" copy value integer! (
						value: load trim value
						set-flag 'workers
						if zero? value [set-flag 'debug]
						repend args ['workers abs value]
					)
; cleanup this mess !					
					| "-vvvvv"	(set-flag 'verbose repend args ['verbosity 5] propagate " -vvvvv")
					| "-vvv"	(set-flag 'verbose repend args ['verbosity 4] propagate " -vvv")
					| "-vv"		(set-flag 'verbose repend args ['verbosity 2] propagate " -vv")
					| "-v"		(set-flag 'verbose repend args ['verbosity 1] propagate " -v")
					| skip
				]
			]
		]
	]

	boot: has [err][
		if any [
			all [
				encap?
				find system/script/header/encap 'no-window 
			]
			all [
				not encap?
				1 = (system/options/boot-flags and 1) ; -- test -w flag
			]
		][
			set-flag 'no-screen
		]
		
		parse-cmd-line
		
		unless flag? 'bg-process [do-cache %misc/os.r] ; -- can't use any OS calls before that
			
		logger/level: either flag? 'verbose [
			logger/level: either flag? 'no-screen [
				logger/file.log: join %chey-pid- [process-id? %.log]
				'file
			][
				'screen
			]
		][
			none
		]
		
		unless flag? 'bg-process [
			if OS-Windows? [
				if encap? [
					set-working-folders
					insert logger/file.log data-dir
				]
				if all [NT-service? not flag? 'service][set-flag 'tray-only]
			]
			if verbose > 0 [			
				log/info ["cmdline args : " system/script/args]
				log/info ["processed    : " mold args]
				log/info ["boot flags   : " mold flags]
				log/info ["data folder  : " mold data-dir]
			]
		]

		; --- applications dispatcher ---
		if error? set/any 'err try [
			case [
				flag? 'bg-process	[do-bg-process-app]
				flag? 'uninstall	[do-uninstall-app]
				flag? 'tray-only	[do-tray-app]
				true 				[do-cheyenne-app]
			]
		][
			either flag? 'no-screen [
				write/append %crash.log reform [now ":" mold disarm err]
			][
				if value? 's-print [print: :s-print]
				print mold disarm err
				halt
			]
		]
	]
]

cheyenne/boot