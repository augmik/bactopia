/*
========================================================================================
    Functions specific to Bactopia
========================================================================================
*/
import nextflow.util.SysHelper

def get_schemas() {
    def schemas = []
    def is_workflow = params.workflows[params.wf].containsKey('is_workflow')

    if (params.wf == "cleanyerreads") {
        schemas << 'conf/schema/clean-yer-reads.json'
    } else if (params.wf == "teton") {
        schemas << 'conf/schema/teton.json'
    } else if (is_workflow == true) {
        // Named workflow based of Bactopia
        schemas << 'conf/schema/bactopia.json'
    } else {
        // Bactopia Tool
        schemas << 'conf/schema/bactopia-tools.json'
    }

    if (params.workflows[params.wf].containsKey('use_local')) {
        // Some work flows should include local files
        schemas << "conf/schema/local/${params.workflows[params.wf]['use_local']}.json"
    }

    if (params.workflows[params.wf].containsKey('includes')) {
        // Wrapper around multiple workflows
        schemas += _get_include_schemas(params.workflows[params.wf]["includes"])
    }
    if (params.workflows[params.wf].containsKey('modules')) {
        // Workflow or Subworkflow
        schemas += _get_module_schemas(params.workflows[params.wf]["modules"])
    }
    if (params.workflows[params.wf].containsKey('path')) {
        // Module
        schemas << "${params.workflows[params.wf].path}/params.json"
    }

    if (params.containsKey('ask_merlin')) {
        if (params.ask_merlin) {
            // Summon Merlin
            schemas += _get_module_schemas(params.workflows['merlin']["modules"])
        }
    }

    if (params.containsKey('use_bakta')) {
        if (params.use_bakta) {
            // Annotate genomes with Bakta
            schemas += _get_module_schemas(params.workflows['bakta']["modules"])
        } else {
            schemas += "${params.workflows['prokka'].path}/params.json"
        }
    }

    // Load profile specific schemas
    if ("${workflow.profile}".contains('aws')) {
        schemas << "conf/schema/profiles/aws.json"
    }

    if ("${workflow.profile}".contains('gcp')) {
        schemas << "conf/schema/profiles/gcp.json"
    }

    if ("${workflow.profile}".contains('sge')) {
        schemas << "conf/schema/profiles/sge.json"
    }

    if ("${workflow.profile}".contains('slurm')) {
        schemas << "conf/schema/profiles/slurm.json"
    }

    // Custom configs
    if ("${workflow.profile}".contains('arcc')) {
        schemas << "conf/schema/profiles/slurm.json"
    }

    schemas << 'conf/schema/generic.json'
    return schemas
}

def _get_include_schemas(includes) {
    def include_schemas = []
    includes.each { it ->
        if (params.workflows[it].containsKey('modules')) {
            include_schemas += _get_module_schemas(params.workflows[it]['modules'])
        }
    }
    return include_schemas
}

def _get_module_schemas(modules) {
    def module_schemas = []
    modules.each { it ->
        if (params.wf == "cleanyerreads") {
            module_schemas << "${params.workflows[it].path}/params-${params.wf}.json"
        } else if (params.wf == "teton" && (it == "gather" || it == "srahumanscrubber_initdb")) {
            module_schemas << "${params.workflows[it].path}/params-${params.wf}.json"
        } else {
            module_schemas << "${params.workflows[it].path}/params.json"
        }
    }
    return module_schemas
}

def get_resources(profile, max_memory, max_cpus) {
    /* Adjust memory/cpu requests for standard profile only */
    def Map resources = [:]
    resources.MAX_MEMORY = ['standard', 'docker', 'singularity'].contains(profile) ? _get_max_memory(max_memory).GB : (max_memory).GB
    resources.MAX_MEMORY_INT = resources.MAX_MEMORY.toString().split(" ")[0]
    resources.MAX_CPUS = ['standard', 'docker', 'singularity'].contains(profile) ? _get_max_cpus(max_cpus.toInteger()) : max_cpus.toInteger()
    resources.MAX_CPUS_75 = Math.round(resources.MAX_CPUS * 0.75)
    resources.MAX_CPUS_50 = Math.round(resources.MAX_CPUS * 0.50)
    resources.MAX_CPUS_1 = 1
    return resources
}

def _get_max_memory(requested) {
    /* Get the maximum available memory for the given system */
    def available = Math.floor(Double.parseDouble(SysHelper.getAvailMemory().toGiga().toString().split(" ")[0])).toInteger()
    if (available < requested) {
        log.warn "Maximum memory (${requested}) was adjusted to fit your system (${available})"
        return available
    }

    return requested
}

def _get_max_cpus(requested) {
    /* Get the maximum available cpus for the given system */
    def available = SysHelper.getAvailCpus()
    if (available < requested) {
        log.warn "Maximum CPUs (${requested}) was adjusted to fit your system (${available})"
        return available
    }
    
    return requested
}

def print_efficiency(cpus) {
    /* Inform user how local bactiopia run will use resources */
    if (['standard', 'docker', 'singularity'].contains(workflow.profile)) {
        // This is a local run on a single machine
        available = SysHelper.getAvailCpus()
        tasks = available / cpus
        log.info """
            Each task will use ${cpus} CPUs out of the available ${available} CPUs. At most 
            ${tasks} task(s) will be run at a time, this can affect the efficiency 
            of Bactopia. You can use the '-qs' parameter to alter the number of 
            tasks to run at a time (e.g. '-qs 2', means only 2 tasks or a maximum 
            of ${2 * cpus} CPUs will be used at once)
        """.stripIndent()
        log.info ""
    }
}

def is_available_workflow(wf) {
    if (params.available_workflows['bactopia'].contains(wf)) {
        return true
    } else if (params.available_workflows['bactopiatools']['subworkflows'].contains(wf)) {
        return true
    } else if (params.available_workflows['bactopiatools']['modules'].contains(wf)) {
        return true
    } else {
        return false
    }
}

/*
========================================================================================
    Functions modeled from nf-core/modules
========================================================================================
*/
def saveFiles(Map args) {
    /*
    Modeled after nf-core/modules saveFiles function
    
    Example structure of output files:

    <OUTDIR>/
    ├── bactopia-runs
    │   └── <WORKFLOW_NAME>-YYYYMMDD-HHMMSS
    │       └── <PROCESS_NAME>
    |       |   ├── logs
    │       |   └── merged-results
    │       └── <PROCESS_NAME>
    │       |   └── <REF_NAME>
    |       |       ├── logs
    │       |       └── merged-results
    │       ├── logs
    │       ├── nf-reports
    │       └── software-versions
    └── <SAMPLE_NAME>
        ├── main
        │   └── <PROCESS_NAME>
        │       └── logs
        └── tools
            ├── <PROCESS_NAME>
            │   └── <REF_NAME>
            │       └── logs
            └── <PROCESS_NAME>
                └── logs
    */
    def final_output = null
    def filename = ""
    def found_ignore = false
    def logs_subdir = args.containsKey('logs_subdir') ? args.logs_subdir : args.opts.logs_subdir
    def process_name = args.opts.process_name
    def publish_to_base = args.opts.publish_to_base.getClass() == Boolean ? args.opts.publish_to_base : false
    def publish_to_base_list = args.opts.publish_to_base.getClass() == ArrayList ? args.opts.publish_to_base : []
    def goto_base = false
    if (args.filename) {
        if (args.filename.startsWith('.command')) {
            // Its a Nextflow process file, rename to "nf-<PROCESS_NAME>.*"
            ext = args.filename.replace(".command.", "")
            if (args.opts.btype == "comparative") {
                // comparative workflows will have subdir applied later
                if (args.opts.logs_use_prefix) {
                    final_output = "${process_name}/${args.prefix}/logs/${logs_subdir}/nf-${process_name}.${ext}"
                } else {
                    final_output = "${process_name}/logs/${logs_subdir}/nf-${process_name}.${ext}"
                }
            } else {
                final_output = "${process_name}/${args.opts.subdir}/logs/${logs_subdir}/nf-${process_name}.${ext}"
            }
        } else if (args.filename.endsWith('.log') || args.filename.endsWith('.err') || args.filename.endsWith('.stdout') || args.filename.endsWith('.stderr') || args.filename.equals('versions.yml')) {
            // Its a version file or program specific log files
            if (args.opts.btype == "comparative") {
                // comparative workflows will have subdir applied later
                if (args.opts.logs_use_prefix) {
                    final_output = "${process_name}/${args.prefix}/logs/${logs_subdir}/${args.filename}"
                } else {
                    final_output = "${process_name}/logs/${logs_subdir}/${args.filename}"
                }
            } else {
                final_output = "${process_name}/${args.opts.subdir}/logs/${logs_subdir}/${args.filename}"
            }
        } else {
            // Its a program output
            filename = args.filename
            if (filename.startsWith("results/")) {
                filename = filename.replace("results/","")
            }

            if (publish_to_base == true) {
                goto_base = true
                final_output = filename
            } else {
                if (args.opts.btype == "comparative") {
                    // comparative workflows will have subdir applied later
                    final_output = "${process_name}/${filename}"
                } else {
                    final_output = "${process_name}/${args.opts.subdir}/${filename}"
                }
            }

            // Exclude files that should be ignored
            args.opts.ignore.each {
                if (filename.endsWith("${it}")) {
                    final_output = null
                }
            }

            // Publish specific files to base
            publish_to_base_list.each {
                if (filename.endsWith("${it}")) {
                    goto_base = true
                    final_output = filename
                }
            }
        }
        
        if (final_output) {
            if (args.opts.btype == "main" || args.opts.btype == "tools") {
                // outdir/<SAMPLE_NAME>/{main|tools}
                if (goto_base) {
                    // my-sample/assembly-error.txt
                    final_output = "${args.prefix}/${final_output}"
                } else {
                    // my-sample/bactopia-main/assembler
                    if (process_name == "bakta" || process_name == "prokka") {
                        // my-sample/bactopia-main/<process_name>/<output>
                        final_output = "${args.prefix}/${args.opts.btype}/annotator/${final_output}"
                    } else {
                        // my-sample/bactopia-main/<output>
                        final_output = "${args.prefix}/${args.opts.btype}/${final_output}"
                    }
                }
            } else {
                // $outdir/bactopia-runs/$rundir
                // bactopia-runs/<WORKFLOW>-YYYYMMDD-HHMMSS/pangenome/core-genome.aln.gz
                final_output = "bactopia-runs/${args.rundir}/${final_output}"
            }
            // Replace any double slashes
            final_output = final_output.replace("//", "/")
        }
    }

    return final_output
}


def initOptions(Map args, String process_name) {
    /* Function to initialise default values and to generate a Groovy Map of available options for nf-core modules */
    def Map options = [:]
    options.args            = args.args ?: ''
    options.args2           = args.args2 ?: ''
    options.args3           = args.args3 ?: ''
    options.ignore          = args.ignore ?: []
    options.is_main         = args.is_main ?: false
    options.is_module       = args.is_module ?: false
    options.is_db_download  = args.is_db_download ?: false
    options.subdir          = args.subdir ?: ''
    options.logs_subdir     = args.logs_subdir ?: ''
    options.process_name    = args.process_name ?: process_name
    options.publish_to_base = args.publish_to_base ?: false
    options.suffix          = args.suffix ?: ''
    options.logs_use_prefix = args.logs_use_prefix ?: false

    return options
}
