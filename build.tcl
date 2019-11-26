# SPDX-License-Identifier: Apache-2.0
#
################################################################################
##
## Copyright 2017-2019 Missing Link Electronics, Inc.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
################################################################################
##
##  File Name      : build.tcl
##  Initial Author : Andreas Braun <andreas.braun@missinglinkelectronics.com>
##
################################################################################
##
##  File Summary   : Vivado build TCL script executed from build.sh
##
################################################################################

################################################################################
## Declare build steps

set build_steps(prj)       0
set build_steps(exec_tcl)  1
set build_steps(sim_prep)  2
set build_steps(sim)       3
set build_steps(package)   4
set build_steps(synth_ooc) 5
set build_steps(synth)     6
set build_steps(impl)      7
set build_steps(bit)       8

################################################################################
## Script command processing

# Command line option defaults
set flavor           "."
set start_step       $build_steps(prj)
set end_step         $build_steps(bit)
set generic_tupels   [list]
set vdefine_tupels   [list]
set ign_vivado_vers  0
set tcl_files        [list]

# Process command line options
set num_arg $argc
if {$num_arg > 0} {
    for {set i 0} {$i < $num_arg} {incr i} {
        set arg [lindex $argv $i]
        if {[regexp {^script_dir=(.*)$} $arg match val] == 1} {
            set scripts_dir "[file normalize "${val}"]"
        }
        if {[regexp {^base_dir=(.*)$} $arg match val] == 1} {
            set base_dir "[file normalize "${val}"]"
        }
        if {[regexp {^flavor=(.*)$} $arg match val] == 1} {
            set flavor "$val"
        }
        if {[regexp {^xpr_name=(.*)$} $arg match val] == 1} {
            set xpr_name "$val"
        }
        if {[regexp {^config_dict_name=(.*)$} $arg match val] == 1} {
            set config_dict_name $val
        }
        if {[regexp {^start_step=(.*)$} $arg match val] == 1} {
            set start_step $build_steps($val)
        }
        if {[regexp {^end_step=(.*)$} $arg match val] == 1} {
            set end_step $build_steps($val)
        }
        if {[regexp {^generic=(.*)$} $arg match val] == 1} {
            lappend generic_tupels $val
        }
        if {[regexp {^vdefine=(.*)$} $arg match val] == 1} {
            lappend vdefine_tupels $val
        }
        if {[regexp {^ign_vivado_vers.*} $arg] == 1} {
            set ign_vivado_vers 1
        }
        if {[regexp {^tcl_file=(.*)$} $arg match val] == 1} {
            lappend tcl_files $val
        }
    }
}

set tcl_files [lreverse $tcl_files]

if {![info exists scripts_dir]} {
    puts "Please set the scripts directory or use build.sh"
    exit 2
}
if {![info exists base_dir]} {
    puts "Please set the base directory or use build.sh"
    exit 2
}
if {![info exists xpr_name]} {
    puts "Please set XPR name or use build.sh"
    exit 2
}

################################################################################
## Paths

set project_dir  "[pwd]"
set flavor_dir   "[file normalize "${base_dir}/${flavor}"]"

################################################################################
## Build helpers

set helper_tcl_file "[file normalize "${scripts_dir}/helper.tcl"]"
source "${helper_tcl_file}"

set config_dict_file "[file normalize "${base_dir}/${flavor}/${config_dict_name}"]"
if {[file exists "${config_dict_file}"]} {
    set config_dict [restore_dict "${config_dict_file}"]
} else {
    puts "ERROR: Configuration dictionary file not found: ${config_dict_file}"
    exit 2
}

set bvars_file "[file normalize "${project_dir}/bvars.dict"]"
if {[file exists "${bvars_file}"]} {
    set bvars_dict [restore_dict "${bvars_file}"]
} else {
    set bvars_dict [dict create]
}

## Set/reset error counters
# Vivado log file parsing defaults
dict set bvars_dict VMERR   0
dict set bvars_dict VMCWARN 0
dict set bvars_dict VMWARN  0
# GIT command execution error
dict set bvars_dict GITERR 0

# Store script arguments
dict set bvars_dict BDIR  $base_dir
dict set bvars_dict FLAV  $flavor
dict set bvars_dict XPR   $xpr_name
dict set bvars_dict CDICT $config_dict_name
dict set bvars_dict SSTEP $start_step
dict set bvars_dict ESTEP $end_step
dict set bvars_dict IGNVV $ign_vivado_vers
dict set bvars_dict EXTCL $tcl_files
dict set bvars_dict CDF   $config_dict_file

################################################################################
## Set project parameters from configuration-dictionary

set mdt_params [dict get $config_dict "MDT_PARAMS"]
dict for {key val} $mdt_params {
    set "${key}" "${val}"
}

if {[dict exists $config_dict "OPT_PARAMS"]} {
    set opt_params [dict get $config_dict "OPT_PARAMS"]
    dict for {key val} $opt_params {
        set "${key}" "${val}"
    }
}

if {[dict exists $config_dict "SIM_PARAMS"]} {
    set sim_params [dict get $config_dict "SIM_PARAMS"]
    dict for {key val} $sim_params {
        set "${key}" "${val}"
    }
}

################################################################################
## Setup hook scripts

# Helper tcl path to be used in hooks
dict set bvars_dict HELPER $helper_tcl_file

# Build system hooks
dict set bvars_dict HOOKS "sys_synth_post" \
    "[file normalize "${scripts_dir}/hooks/sys_synth_post.tcl"]" \
    "[file normalize "${scripts_dir}/hooks/sys_write_netlist.tcl"]"
dict set bvars_dict HOOKS "sys_impl_pre" \
    "[file normalize "${scripts_dir}/hooks/sys_impl_pre.tcl"]"
dict set bvars_dict HOOKS "sys_impl_post" \
    "[file normalize "${scripts_dir}/hooks/sys_impl_post.tcl"]"
dict set bvars_dict HOOKS "sys_bit_pre" \
    "[file normalize "${scripts_dir}/hooks/sys_bit_pre.tcl"]"
dict set bvars_dict HOOKS "sys_bit_post" \
    "[file normalize "${scripts_dir}/hooks/sys_bit_post.tcl"]"

# User hooks
if {[dict exists $config_dict "USER_HOOKS"]} {
    set user_hooks [dict get $config_dict "USER_HOOKS"]
    dict for {build_step filenames} $user_hooks {
        set build_step_hooks [list]
        foreach file $filenames {
            lappend build_step_hooks "[file normalize "${flavor_dir}/${file}"]"
        }
        dict set bvars_dict HOOKS $build_step $build_step_hooks
    }
}

################################################################################

# Vivado version verification
set vivado_version [version -short]
if {[lsearch -exact $req_vivado_vers $vivado_version] < 0} {
    puts ""
    if {$ign_vivado_vers == 1} {
        puts -nonewline "WARNING: You are using Vivado '$vivado_version' and "
        puts "not the recommended '[lindex $req_vivado_vers 0]'!"
        puts -nonewline "The build will continue since you chose to ignore the "
        puts "incorrect Vivado version"
    } else {
        puts -nonewline "ERROR: Please use Vivado '[lindex $req_vivado_vers 0]'"
        puts " and not '$vivado_version' to build the system!"
        puts -nonewline "You can prevent this error message by providing the "
        puts "'-i' argument to build.sh"
        exit 2
    }
} elseif {![string equal "[lindex $req_vivado_vers 0]" "$vivado_version"]} {
    puts -nonewline "WARNING: You are using Vivado '$vivado_version' and not "
    puts "the recommended '[lindex $req_vivado_vers 0]'!"
}

################################################################################
## Check simulation environment

if {[catch {set pre_comp_simlib_dir $::env(PRECOMP_SIM_LIBS)}]} {
    puts "INFO: Simulation environment variable PRECOMP_SIM_LIBS not set"
} else {
    set pre_comp_simlib_dir "[file normalize "${pre_comp_simlib_dir}"]"
    puts "INFO: Simulation environment variable set to '${pre_comp_simlib_dir}'"
}

if {[info exists target_simulator]} {
    if {[string equal $target_simulator "XSim"]} {
        set sim_lib_valid 1
        set pre_comp_simlib_dir ""
    } elseif {[info exists pre_comp_simlib_dir] && \
             ![string equal $pre_comp_simlib_dir ""]} {
        set rpt_file "[file normalize "${project_dir}/report_simlib_info.log"]"
        set code [catch {report_simlib_info -file $rpt_file $pre_comp_simlib_dir}]

        set i 0
        set fid [open $rpt_file r]
        while {[gets $fid line] > -1} {incr i}
        close $fid

        if {[expr {$i > 100}]} {
            set sim_lib_valid 1
        } else {
            puts -nonewline "WARNING: Invalid pre-compiled simulation libraries"
            puts -nonewline " for target simulator '${target_simulator}' located "
            puts -nonewline "in '${pre_comp_simlib_dir}'. Check Simlib-info "
            puts "report file '${rpt_file}' for details"
        }
    } else {
        puts -nonewline "WARNING: No path to pre-compiled simulation libraries "
        puts "set for target simulator '${target_simulator}'"
    }
} else {
    set target_simulator "XSim"
}
set target_simulator_lc [string tolower $target_simulator]

################################################################################
## Set up project

if {$start_step == $build_steps(prj)} {
    save_dict "${bvars_file}" $bvars_dict
    exec_usr_hooks "bld_prj_pre" $bvars_dict

    set fileset_constrs_name "constrs_1"
    set fileset_sources_name "sources_1"
    set fileset_sim_name     "sim_1"

    if {![info exists board]} {
        set board ""
    }

    puts "Creating project \"$xpr_name\" in $project_dir"
    puts "Using $part FPGA on the $board board"

    puts "Create filesets constraints, source, simulation"
    create_project $xpr_name $project_dir -part $part -force
    set cur_prj [get_projects $xpr_name]

    set_property board_part       $board            $cur_prj
    set_property target_language  $target_language  $cur_prj
    set_property default_lib      $default_lib      $cur_prj
    set_property target_simulator $target_simulator $cur_prj
    if {[info exists sim_lib_valid]} {
        set_property "compxlib.${target_simulator_lc}_compiled_library_dir" \
                $pre_comp_simlib_dir $cur_prj
    }
    if {[info exists simulator_language]} {
        set_property simulator_language $simulator_language $cur_prj
    }

    # IP-XACT repositories relative to flavor
    if {[info exists ipxact_dir]} {
        puts "Parsing IP-XACT repositories from configuration file ..."
        set ipxact_dirs [list]
        foreach value $ipxact_dir {
            lappend ipxact_dirs "[file normalize "${flavor_dir}/${value}"]"
        }
        if {[package vcompare [version -short] 2014.3] >= 0} {
            set_property ip_repo_paths $ipxact_dirs $cur_prj
        } else {
            set_property ip_repo_paths $ipxact_dirs [current_fileset]
        }
    }

    # Set IP Cache
    if {[info exists use_ip_cache_dir]} {
        if {"${use_ip_cache_dir}" == ""} {
            set use_ip_cache_dir "[file normalize "${project_dir}/../ip_cache"]"
        } else {
            set use_ip_cache_dir "[file normalize \
                    "${flavor_dir}/${use_ip_cache_dir}"]"
        }
        file mkdir $use_ip_cache_dir
        config_ip_cache -import_from_project -use_cache_location \
                "${use_ip_cache_dir}"
    }

    if {[string equal [get_filesets -quiet $fileset_constrs_name] ""]} {
        create_fileset -constrset $fileset_constrs_name
    }
    set fileset_constrs [get_filesets $fileset_constrs_name]

    if {[string equal [get_filesets -quiet $fileset_sources_name] ""]} {
        create_fileset -srcset $fileset_sources_name
    }
    set fileset_sources [get_filesets $fileset_sources_name]

    if {[string equal [get_filesets -quiet $fileset_sim_name] ""]} {
    	create_fileset -simset $fileset_sim_name
    }
    set fileset_sim [get_filesets $fileset_sim_name]

    # Process .f and return filelist
    proc process_filelist {filelist_path files_dir} {
        set filelist    [list]
        set fd_filelist [open "${filelist_path}" r]
        while {[gets $fd_filelist line] >= 0} {
            if {![regexp {^(\s*#.*|^$)} $line]} {
                set filepath "[file normalize "${files_dir}/${line}"]"
                if {![file exists $filepath]} {
                    puts "ERROR: File not found '$filepath'"
                    exit 2
                } else {
                    lappend filelist $filepath
                    puts $filepath
                }
            }
        }
        close $fd_filelist
        return $filelist
    }

    ## Process filelists
    # Iterate over all filelists and add named files from given directory to
    # fileset. Paths are relative to flavor directory

    # Process constraints set
    set filelist_constr [list]
    if {[dict exists $config_dict "CONSTR_SET"]} {
        puts "Adding files to constraints set ..."
        set constr_set [dict get $config_dict "CONSTR_SET"]
        dict for {constr_f files_dir} $constr_set {
            set filelist_constr [concat $filelist_constr [process_filelist \
            "${flavor_dir}/${constr_f}" "${flavor_dir}/${files_dir}"]]
        }
        if {[llength $filelist_constr] == 0} {
            puts "WARNING: No files have been added to constraints set"
        } else {
            add_files -norecurse -fileset $fileset_constrs $filelist_constr
        }
    }

    # Process source set
    set filelist_src [list]
    if {[dict exists $config_dict "SRC_SET"]} {
        puts "Adding files to source set ..."
        set src_set [dict get $config_dict "SRC_SET"]
        dict for {src_f files_dir} $src_set {
            set filelist_src [concat $filelist_src [process_filelist \
            "${flavor_dir}/${src_f}" "${flavor_dir}/${files_dir}"]]
        }
        if {[llength $filelist_src] == 0} {
            puts "WARNING: No files have been added to source set"
        } else {
            add_files -norecurse -fileset $fileset_sources $filelist_src
        }
    }

    # Process simulation set
    set filelist_sim [list]
    if {[dict exists $config_dict "SIM_SET"]} {
        puts "Adding files to simulation set ..."
        set sim_set [dict get $config_dict "SIM_SET"]
        dict for {sim_f files_dir} $sim_set {
            set filelist_sim [concat $filelist_sim [process_filelist \
            "${flavor_dir}/${sim_f}" "${flavor_dir}/${files_dir}"]]
        }
        if {[llength $filelist_sim] == 0} {
            puts "WARNING: No files have been added to simulation set"
        } else {
            add_files -norecurse -fileset $fileset_sim $filelist_sim
        }
    }

    # Process include set
    if {[dict exists $config_dict "INCL_SET"]} {
        puts "Parsing INCL_SET files ..."
        set filelist_incl [list]
        set incl_set [dict get $config_dict "INCL_SET"]
        dict for {incl_f files_dir} $incl_set {
            set filelist_incl [concat $filelist_incl [process_filelist \
            "${flavor_dir}/${incl_f}" "${flavor_dir}/${files_dir}"]]
        }
        if {[llength $filelist_incl] == 0} {
            puts "WARNING: No directories have been included to source and simulation set"
        } else {
            set incl_file_dirs [list]
            foreach incl_file $filelist_incl {
                lappend incl_file_dirs [file dirname $incl_file]
            }
            set incl_file_dirs [lsort -unique $incl_file_dirs]
            puts "Adding include directories to source and simulation set"
            foreach incl_file_dir $incl_file_dirs {
                puts "${incl_file_dir}"
            }
            set_property include_dirs $incl_file_dirs $fileset_sources
            set_property include_dirs $incl_file_dirs $fileset_sim
        }
    }

    # Process simulation include set
    if {[dict exists $config_dict "SIM_INCL_SET"]} {
        puts "Parsing SIM_INCL_SET files ..."
        set filelist_incl [list]
        set incl_set [dict get $config_dict "SIM_INCL_SET"]
        dict for {incl_f files_dir} $incl_set {
            set filelist_incl [concat $filelist_incl [process_filelist \
            "${flavor_dir}/${incl_f}" "${flavor_dir}/${files_dir}"]]
        }
        if {[llength $filelist_incl] == 0} {
            puts "WARNING: No directories have been included to simulation set"
        } else {
            set incl_file_dirs [list]
            foreach incl_file $filelist_incl {
                lappend incl_file_dirs [file dirname $incl_file]
            }
            set incl_file_dirs [lsort -unique $incl_file_dirs]
            puts "Adding include directories to simulation set"
            foreach incl_file_dir $incl_file_dirs {
                puts "${incl_file_dir}"
            }
            set_property include_dirs $incl_file_dirs $fileset_sim
        }
    }

    # Process tcl set
    set filelist_tcl [list]
    if {[dict exists $config_dict "TCL_SET"]} {
        puts "Sourcing TCL files ..."
        set tcl_set [dict get $config_dict "TCL_SET"]
        dict for {tcl_f files_dir} $tcl_set {
            set filelist_tcl [concat $filelist_tcl [process_filelist \
            "${flavor_dir}/${tcl_f}" "${flavor_dir}/${files_dir}"]]
        }
        if {[llength $filelist_tcl] == 0} {
            puts "WARNING: No TCL files have been sourced"
        } else {
            foreach tcl_file $filelist_tcl {
                if {[file exists "${tcl_file}"]} {
                    source "${tcl_file}"
                } else {
                    puts "WARNING: TCL file does not exist: ${tcl_file}"
                }
            }
        }
    }

    if {[info exists debug_target]} {
        # If set but empty, use default name
        if {"${debug_target}" == ""} {
            set debug_target "debug.xdc"
        }
        set debug_constrs_file [get_files -quiet "${debug_target}"]
        # Check if file exists, if not, create it local to the project
        if {[llength $debug_constrs_file] == 0} {
            puts "Create empty constraints file '${debug_target}' \
                    for debug statements and mark the file as target ..."
            set debug_constrs_dir "[file normalize \
                    "${project_dir}/${xpr_name}.srcs/${fileset_constrs_name}"]"
            file mkdir $debug_constrs_dir
            set debug_constrs_file "[file normalize \
                    "${debug_constrs_dir}/${debug_target}"]"
            close [ open $debug_constrs_file w ]
            add_files -fileset $fileset_constrs_name $debug_constrs_file
        }
        set_property target_constrs_file $debug_constrs_file $fileset_constrs
    } else {
        set debug_target ""
    }
    dict set bvars_dict DBGT [file rootname "${debug_target}"]

    ############################################################################

    # Pass generics to top level HDL
    if {[dict exists $config_dict "GENERICS"]} {
        puts "Parsing generics from configuration file ..."
        set generics [dict get $config_dict "GENERICS"]
        dict for {gen_name gen_value} $generics {
            # Insert at the beginning of the list, to let the values be
            # overridden by generics passed from command line.
            set generic_tupels [linsert $generic_tupels 0 \
                    "${gen_name}=${gen_value}"]
        }
    }
    if {[llength $generic_tupels] > 0} {
        set_property generic $generic_tupels $fileset_sources
    }

    if {[dict exists $config_dict "VERILOG_OPTIONS"]} {
        set vopts_dict [dict get $config_dict "VERILOG_OPTIONS"]

        # Include files search path relative to flavor
        if {[dict exists $vopts_dict "INCL_DIRS"]} {
            puts "Parsing Verilog include directories from configuration file ..."
            set vincl_dirs [list]
            set incl_dirs_key [dict get $vopts_dict "INCL_DIRS"]
            foreach value $incl_dirs_key {
                lappend vincl_dirs "[file normalize "${flavor_dir}/${value}"]"
            }
            set_property include_dirs $vincl_dirs $fileset_sources
        }

        # Pass Verilog defines to top level HDL
        if {[dict exists $vopts_dict "DEFINES"]} {
            puts "Parsing Verilog defines from configuration file ..."
            set vdefines [dict get $vopts_dict "DEFINES"]
            dict for {vdef_name vdef_value} $vdefines {
                # Insert at the beginning of the list, to let the values be
                # overridden by verilog defines passed from command line.
                set vdefine_tupels [linsert $vdefine_tupels 0 \
                        "${vdef_name}=${vdef_value}"]
            }
        }

        # Pass Verilog defines to Simulation
        if {[dict exists $vopts_dict "SIM_DEFINES"]} {
            puts "Parsing Verilog Simulation defines from configuration file ..."
            set vsimdefine_tupels [list]
            set vsimdefines [dict get $vopts_dict "SIM_DEFINES"]
            dict for {vdef_name vdef_value} $vsimdefines {
                lappend vsimdefine_tupels "${vdef_name}=${vdef_value}"
            }
            set_property verilog_define $vsimdefine_tupels $fileset_sim
        }
    }
    if {[llength $vdefine_tupels] > 0} {
        set_property verilog_define $vdefine_tupels $fileset_sources
    }

    dict set bvars_dict GNRCS [regsub -all -line {=} "${generic_tupels}" " "]
    dict set bvars_dict VDEFS [regsub -all -line {=} "${vdefine_tupels}" " "]

    ############################################################################

    puts "Setting ${hdl_top_module_name} as top-level module ..."
    set_property top $hdl_top_module_name $fileset_sources

    puts "Updating compile order on fileset_sources ..."
    update_compile_order -fileset $fileset_sources

    if {[info exists sim_top_module_name]} {
        puts "Setting ${sim_top_module_name} as test bench top-level module ..."
        set_property top     $sim_top_module_name $fileset_sim
        set_property top_lib $default_lib         $fileset_sim

        puts "Updating compile order on fileset_sim ..."
        update_compile_order -fileset $fileset_sim
    }

    ############################################################################

    if {[info exists sim_time] && ![string equal $sim_time ""]} {
        set_property -name "${target_simulator_lc}.simulate.runtime" \
                -value "${sim_time}" -objects $fileset_sim
    }

    if {[info exists sim_log_all] && ![string equal $sim_log_all ""]} {
        set_property -name "${target_simulator_lc}.simulate.log_all_signals" \
                -value "${sim_log_all}" -objects $fileset_sim
    }

    if {[info exists sim_wave_do] && ![string equal $sim_wave_do ""]} {
        set_property -name "${target_simulator_lc}.simulate.custom_wave_do" \
                -value "${sim_wave_do}" -objects $fileset_sim
    }

    ############################################################################
    ## Out of context runs

    puts "Creating out of context runs ..."
    if {[dict exists $config_dict "OOC_MODULES"]} {
        set ooc_modules [dict get $config_dict "OOC_MODULES"]
        dict for {ooc_module ooc_fileset} $ooc_modules {
            set filelist_ooc_constr [list]
            set ooc_module_dict [dict get $ooc_modules "${ooc_module}"]
            dict for {ooc_constr_f ooc_files_dir} $ooc_module_dict {
                set filelist_ooc_constr [concat $filelist_ooc_constr \
                        [process_filelist \
                        "${flavor_dir}/${ooc_constr_f}" \
                        "${flavor_dir}/${ooc_files_dir}"]]
            }

            # Create OOC fileset
            set fileset_ooc_module "${ooc_module}_ooc"
            create_fileset -blockset -define_from "${ooc_module}" \
                    "${fileset_ooc_module}"

            if {[llength $filelist_ooc_constr] == 0} {
                puts "WARNING: No files have been added to OOC constraints set\
                        for module '${ooc_module}'"
            } else {
                add_files -norecurse -fileset $fileset_ooc_module \
                        $filelist_ooc_constr
            }
        }
    }

    ############################################################################
    ## In context run

    puts "Creating synthesis run ..."
    set run_synth_name "synth_1"
    if {[string equal [get_runs -quiet $run_synth_name] ""]} {
        create_run $run_synth_name -part $part \
                -flow "Vivado Implementation ${vivado_year}" \
                -srcset $fileset_sources -constrset $fileset_constrs
    }
    set run_synth [get_runs $run_synth_name]

    puts "Setting active run to synthesis run ..."
    current_run $run_synth

    if {[dict exists $config_dict "SYNTH_STRAT"]} {
        set synth_strat [dict get $config_dict "SYNTH_STRAT"]
        dict for {key value} $synth_strat {
            set_property "${key}" "${value}" $run_synth
        }
    }

    ############################################################################

    puts "Creating implementation run ..."
    set run_impl_name "impl_1"
    if {[string equal [get_runs -quiet $run_impl_name] ""]} {
        create_run $run_impl_name -part $part -parent_run $run_synth \
                -flow "Vivado Implementation ${vivado_year}" \
                -constrset $fileset_constrs
    }
    set run_impl [get_runs $run_impl_name]

    if {[dict exists $config_dict "IMPL_STRAT"]} {
        set impl_strat [dict get $config_dict "IMPL_STRAT"]
        dict for {key value} $impl_strat {
            set_property "${key}" "${value}" $run_impl
        }
    }

    ############################################################################
    # Special file properties

    # Use file only in defined steps
    if {[dict exists $config_dict "USE_FILE_ONLY_IN_STEPS"]} {
        set file_step_dict [dict get $config_dict "USE_FILE_ONLY_IN_STEPS"]
        dict for {file_name step} $file_step_dict {
            set_property USED_IN "$step" [get_files $file_name]
        }
    }

    # Set constraints file processing order EARLY, NORMAL, LATE
    if {[dict exists $config_dict "CONSTR_PROC_ORDER"]} {
        set file_proc_order_dict [dict get $config_dict "CONSTR_PROC_ORDER"]
        dict for {file_name order} $file_proc_order_dict {
            set_property PROCESSING_ORDER "$order" [get_files $file_name]
        }
    }

    ############################################################################
    # Hook setup

    # Copy template hook file to build folder and replace build step string. Set
    # hook as Vivado's pre/post step property. Use hook as entry point to
    # execute user hooks
    if {[dict exists $bvars_dict "HOOKS"]} {
        # Template hook file
        set hook_src "${scripts_dir}/templates/viv_sys_hook.tcl"

        set hooks [dict get $bvars_dict "HOOKS"]
        dict for {build_step filenames} $hooks {
            if {[string match "viv_sim_pre" $build_step]} {
                # Simulation pre
                set hook_dest "${project_dir}/hooks/viv_sys_sim_pre.tcl"
                copy_sub $hook_src $hook_dest "<HOOK_STEP>" $build_step

                set_property -name "${target_simulator_lc}.compile.tcl.pre" \
                        -value $hook_dest -objects $fileset_sim
            } elseif {[string match "viv_sim_post" $build_step]} {
                # Simulation post
                set hook_dest "${project_dir}/hooks/viv_sys_sim_post.tcl"
                copy_sub $hook_src $hook_dest "<HOOK_STEP>" $build_step

                set_property -name "${target_simulator_lc}.simulate.tcl.post" \
                        -value $hook_dest -objects $fileset_sim
            } elseif {[string match "viv_impl_*" $build_step]} {
                # Implementation pre/post
                set split_step  [split $build_step "_"]
                set step_impl   [join [lrange $split_step 2 end-1] "_"]
                set step_prefix [lindex $split_step end]

                set hook_dest "${project_dir}/hooks/viv_sys_impl_${step_impl}.${step_prefix}.tcl"
                copy_sub $hook_src $hook_dest "<HOOK_STEP>" $build_step

                set_property steps.${step_impl}.tcl.${step_prefix} $hook_dest \
                        $run_impl
            } elseif {[string match "viv_bit_post" $build_step]} {
                # Bitstream post
                set hook_dest "${project_dir}/hooks/viv_sys_bit_post.tcl"
                copy_sub $hook_src $hook_dest "<HOOK_STEP>" $build_step

                set_property steps.write_bitstream.tcl.post $hook_dest $run_impl
            }
        }
    }

    # Synthesis pre/post
    set_property steps.synth_design.tcl.pre "[file normalize \
            "${scripts_dir}/hooks/viv_sys_synth_pre.tcl"]" $run_synth
    set_property steps.synth_design.tcl.post "[file normalize \
            "${scripts_dir}/hooks/viv_sys_synth_post.tcl"]" $run_synth

    # Bitstream pre
    set_property steps.write_bitstream.tcl.pre "[file normalize \
            "${scripts_dir}/hooks/viv_sys_bit_pre.tcl"]" $run_impl

    ############################################################################

    puts "INFO: Creating project done"

    save_dict "${bvars_file}" $bvars_dict
    exec_usr_hooks "bld_prj_post" $bvars_dict
} else {
    puts "INFO: Opening project ${xpr_name}.xpr"
    open_project "${xpr_name}.xpr"
}

################################################################################
## Update build helper

set run_synth [current_run -synthesis]
set run_impl  [current_run -implementation]

# Vivado context will be lost in Hooks
dict set bvars_dict RSYNTH "${run_synth}"
dict set bvars_dict RIMPL  "${run_impl}"
dict set bvars_dict RSIM   [current_fileset -simset]
dict set bvars_dict PNAME  [get_projects]
dict set bvars_dict TLNAME [get_property top [current_fileset]]
save_dict "${bvars_file}" $bvars_dict

################################################################################
## Execute TCL script files
foreach tcl_file $tcl_files {
    if {[file exists "${tcl_file}"]} {
        puts "INFO: Execute TCL script ${tcl_file}"
        source "${tcl_file}"
    } else {
        puts "ERROR: TCL file does not exist: '${tcl_file}'"
        exit 2
    }
}

################################################################################
## Generate simulation scripts
if {$start_step == $build_steps(sim_prep) || $end_step == $build_steps(sim_prep)} {
    puts "INFO: Generate simulation scripts"
    set sim_set [current_fileset -simset]
    update_compile_order -fileset $sim_set
    launch_simulation -scripts_only
    set simscripts_dir "[file normalize \
        "${project_dir}/${xpr_name}.sim/${sim_set}/behav/${target_simulator_lc}/"]"
    puts "INFO: Simulation scripts generated in '${simscripts_dir}'"

    exit 0
}

################################################################################
## Run simulation
if {$start_step == $build_steps(sim) || $end_step == $build_steps(sim)} {
    puts "INFO: Start simulation"
    update_compile_order -fileset [current_fileset -simset]
    launch_simulation
    puts "Running simulation ..."

    exit 0
}

################################################################################
## IP-XACT package project
if {$start_step == $build_steps(package) || \
    $end_step   == $build_steps(package)} {
    puts "Package project in IP-XACT format"
    puts "Running Syntax Check ..."
    set cs [check_syntax -return_string -quiet]
    if {[regexp {^CRITICAL WARNING:.*$} $cs] == 1} {
        puts $cs
        puts "ERROR: Syntax Check failed"
        exit 2
    } else {
        puts "Syntax Check passed"
    }
    if {[dict exists $config_dict "PACKAGE_IP"]} {
        # Parse dictionary section PACKAGE_IP
        set package_ip_dict [dict get $config_dict "PACKAGE_IP"]
        if {[dict exists $package_ip_dict "zip_name"]} {
            set zip_name [dict get $package_ip_dict "zip_name"]
        } else {
            set zip_name "packaged-ip.zip"
        }
        if {![dict exists $package_ip_dict "ident"]} {
            puts "ERROR: Key 'ident' of section 'PACKAGE_IP' not found in dictionary"
            exit 2
        }
        set ident_dict [dict get $package_ip_dict "ident"]
        dict for {key value} $ident_dict {
            set "${key}" "${value}"
        }
        if {[dict exists $package_ip_dict "container_dir"]} {
            set container_dir [dict get $package_ip_dict "container_dir"]
            set container_dir "[file normalize \
                    "${flavor_dir}/${container_dir}"]"
        } else {
            set container_dir "${project_dir}"
        }

        # Set default values
        if {[string equal $ipname ""]} {
            set ipname "custom-ip"
        }
        if {[string equal $version ""]} {
            set version "1.0"
        }
        if {[string equal $core_revision ""]} {
            set core_revision "1"
        }

        # Set IP output directory
        set root_dir "[file normalize "${container_dir}/${ipname}_v${version}"]"

        # Block design projects require XCI-packaging
        set gen_files_arg ""
        if {[string equal -nocase $package_xci "false"] && \
            [string equal $bd_name ""]} {
            set gen_files_arg "-generated_files"
        }

        set bstamp [time_stamp]
        set flv_name [dict get $bvars_dict "FLAV"]
        if {[string equal $flv_name "."]} {
            set flv_name ""
        }
        set dict_name [dict get $bvars_dict "CDICT"]
        set dict_name [file rootname [file tail $dict_name]]

        # Create git branch with all uncommitted changes
        cd $base_dir
        set build_branch "build_${flv_name}${dict_name}_${bstamp}"
        set gstamp [list "ERROR" 3]
        if {[set error [catch {git_exists}]]} {
            if {$error == 2} {
                puts "Skipping GIT build commit"
                set gstamp [list "" 0]
            }
        } elseif {[catch {git_stamp "${build_branch}"} result]} {
            puts "Failed packaging GIT build commit"
        } else {
            set gstamp $result
        }
        lassign $gstamp bcommit bctype
        if {$bctype == 3} {
            puts "ERROR: Failed GIT build commit. Continue packaging ..."
            set git_err [dict get $bvars_dict "GITERR"]
            dict set bvars_dict GITERR [expr {$git_err + 1}]
        }
        cd $project_dir

        # Set output file name
        set result_base [dict get $bvars_dict "PNAME"]
        if {[string length $bstamp] > 0} {
            append result_base "_${bstamp}"
        }
        if {[string length $bcommit] > 0} {
            append result_base "_g${bcommit}-${bctype}"
        }

        set cmd_args [list \
            "-root_dir" "${root_dir}" \
            "${gen_files_arg}" \
            "-set_current" "true"
        ]
        set vers [version -short]
        if {[package vcompare [version -short] 2014.3] >= 0} {
            lappend cmd_args "-import_files"
        }
        if {[package vcompare [version -short] 2014.4] >= 0} {
            lappend cmd_args "-force"
        }
        if {[package vcompare [version -short] 2015] >= 0} {
            lappend cmd_args \
                "-vendor" "${vendor}" \
                "-library" "${lib}" \
                "-taxonomy" "${taxonomy}"
        }
        if {[package vcompare [version -short] 2017.4] >= 0} {
            lappend cmd_args "-module" "${bd_name}"
        }

        # Create IP package project
        eval "ipx::package_project ${cmd_args}"

        # Set IP properties
        set_property vendor_display_name "${ven_disp_name}" [ipx::current_core]
        set_property description         "${description}"   [ipx::current_core]
        set_property display_name        "${display_name}"  [ipx::current_core]
        set_property company_url         "${company_url}"   [ipx::current_core]
        set_property name                "${ipname}"        [ipx::current_core]
        set_property version             "${version}"       [ipx::current_core]
        set_property core_revision       "${core_revision}" [ipx::current_core]
        # Parse IP specific properties
        if {[dict exists $package_ip_dict "component"]} {
            set component [dict get $package_ip_dict "component"]
            foreach val $component {
                eval $val
            }
        }
        if {[dict exists $package_ip_dict "component_tcl"]} {
            set comp_tcl [dict get $package_ip_dict "component_tcl"]
            set comp_tcl_file "[file normalize "${flavor_dir}/${comp_tcl}"]"
            if {[file exists "${comp_tcl_file}"]} {
                source "${comp_tcl_file}"
            } else {
                puts "WARNING: Component TCL file does not exist: ${comp_tcl_file}"
            }
        }

        # END IP specific properties
        ipx::create_xgui_files          [ipx::current_core]
        ipx::update_checksums           [ipx::current_core]
        ipx::save_core                  [ipx::current_core]
        ipx::check_integrity -quiet     [ipx::current_core]

        # Insert result_base into component.xml
        cd "${root_dir}"
        set zip_file "${result_base}_${zip_name}"
        set str "xmlns:vbs=\"${result_base}\""
        set fd [open "component.xml" r+]
        set buf [read $fd]
        set lines [split $buf "\n"]
        set line1 [lindex $lines 1]
        set line1 [split $line1 " "]
        set line1 [linsert $line1 1 $str]
        set line1 [join $line1 " "]
        set lines [lreplace $lines 1 1 $line1]
        set buf [join $lines "\n"]
        seek $fd 0
        puts $fd $buf
        close $fd
        exec zip -r "${zip_file}" "component.xml" "src" "xgui"
        file copy -force -- "${zip_file}" "[file normalize "${project_dir}/"]"
        file delete -force -- "${zip_file}"
        set zip_file "[file normalize "${project_dir}/${zip_file}"]"
        cd "${project_dir}"

        puts "Done packaging project in IP-XACT format. Output file ${zip_file}"
        dict set bvars BCOMMIT $bcommit
        dict set bvars BCTYPE  $bctype
        dict set bvars ZIPFILE $zip_file
        save_dict "${bvars_file}" $bvars_dict

        exit 0
    } else {
        puts "ERROR: Key 'PACKAGE_IP' not found in dictionary"
        exit 2
    }
}

################################################################################
## Execute build process

if {$start_step <= $build_steps(synth_ooc) && \
    $end_step   >= $build_steps(synth_ooc)} {
    puts "Synthesizing all out of context runs ..."
    puts "Running Syntax Check ..."
    set cs [check_syntax -fileset [current_fileset] -return_string -quiet]
    if {[regexp {^CRITICAL WARNING:.*$} $cs] == 1} {
        puts $cs
        puts "ERROR: Syntax Check failed for fileset [current_fileset]"
        exit 2
    } else {
        puts "Syntax Check for fileset [current_fileset] passed"
    }
    set run_list [get_runs -filter "IS_SYNTHESIS == true && NAME != $run_synth"]
    if {[llength $run_list] != 0} {
        foreach run $run_list {
            reset_run $run
        }
        launch_runs $run_list -jobs 4
        foreach run $run_list {
            wait_on_run $run
            if {[get_property PROGRESS $run] != "100%"} {
                puts "ERROR: OOC Synthesis of ${run} failed"
                exit 2
            }
        }
    }
    puts "INFO: Out-Of-Context Synthesis done"
} else {
    puts "INFO: Skipping Out-Of-Context Synthesis step"
}

if {$start_step <= $build_steps(synth) && \
    $end_step   >= $build_steps(synth)} {
    puts "Synthesizing design ..."
    reset_run   $run_synth
    exec_usr_hooks "bld_synth_pre" $bvars_dict
    launch_runs $run_synth -jobs 4
    wait_on_run $run_synth
    if {[get_property PROGRESS $run_synth] != "100%"} {
        puts "ERROR: Synthesis failed"
        exit 2
    }
    exec_usr_hooks "sys_synth_post" $bvars_dict
    exec_usr_hooks "bld_synth_post" $bvars_dict
    puts "INFO: Synthesis done"
} else {
    puts "INFO: Skipping Synthesis step"
}

if {$start_step <= $build_steps(impl) && \
    $end_step   >= $build_steps(impl)} {
    puts "Implementing design ..."
    reset_run   $run_impl
    exec_usr_hooks "sys_impl_pre" $bvars_dict
    exec_usr_hooks "bld_impl_pre" $bvars_dict
    launch_runs $run_impl -jobs 4
    wait_on_run $run_impl
    if {[get_property PROGRESS $run_impl] != "100%"} {
        puts "ERROR: Implementation failed"
        exit 2
    }
    exec_usr_hooks "sys_impl_post" $bvars_dict
    exec_usr_hooks "bld_impl_post" $bvars_dict
    puts "INFO: Implementation done"

    set tns  [get_property STATS.TNS  $run_impl]
    set ths  [get_property STATS.THS  $run_impl]
    set tpws [get_property STATS.TPWS $run_impl]
    if {[expr {$tns != 0}] || [expr {$ths != 0}] || [expr {$tpws != 0}]} {
        set timing_status "FAILED"
    } else {
        set timing_status "OK"
    }
} else {
    puts "INFO: Skipping Implementation step"
}

if {$start_step <= $build_steps(bit) && \
    $end_step   >= $build_steps(bit)} {
    puts "Generating Bitstream ..."
    reset_run   -from_step write_bitstream $run_impl
    exec_usr_hooks "sys_bit_pre" $bvars_dict
    exec_usr_hooks "bld_bit_pre" $bvars_dict
    launch_runs -to_step   write_bitstream $run_impl -jobs 4
    wait_on_run $run_impl
    if {[get_property PROGRESS $run_impl] != "100%"} {
        puts "ERROR: Generating Bitstream failed"
        exit 2
    }
    exec_usr_hooks "sys_bit_post" $bvars_dict
    exec_usr_hooks "bld_bit_post" $bvars_dict
    puts "INFO: Generating Bitstream done"
} else {
    puts "INFO: Skipping Bitstream Generation step"
}

################################################################################
## Print short build summary

# Print the number of all ERRORS, CRITICAL WARNINGS and WARNINGS from vivado.log
set viv_log_file "[file normalize "${project_dir}/vivado.log"]"
set viv_log [split [read [open "${viv_log_file}" r]] "\n"]
set vmwarn  [llength [lsearch -all -regexp $viv_log "^WARNING:"]]
set vmcwarn [llength [lsearch -all -regexp $viv_log "^CRITICAL WARNING:"]]
set vmerr   [llength [lsearch -all -regexp $viv_log "^ERROR:"]]

set bvars_dict [restore_dict "${bvars_file}"]
dict set bvars_dict VMWARN  $vmwarn
dict set bvars_dict VMCWARN $vmcwarn
dict set bvars_dict VMERR   $vmerr
save_dict $bvars_file $bvars_dict

puts "Vivado messages:"
puts "\tWARNINGS=${vmwarn}"
puts "\tCRITICAL WARNINGS=${vmcwarn}"
puts "\tERRORS=${vmerr}"

# Timing report
if {[info exists timing_status]} {
    puts "TIMING ${timing_status}:"
    puts "\tTNS=${tns}"
    puts "\tTHS=${ths}"
    puts "\tTPWS=${tpws}"
}

################################################################################
## Return error level

if {$vmerr} {
    set vmerr 4
}
set giterr [dict get $bvars_dict "GITERR"]
if {$giterr} {
    puts "WARNING: GIT commands failed during build process"
    set giterr 3
}

exit [expr {$vmerr + $giterr}]