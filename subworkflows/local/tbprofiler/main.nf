//
// tbprofiler - Detect resistance and lineages of Mycobacterium  tuberculosis genomes
//
include { initOptions } from '../../../lib/nf/functions'
options = initOptions(params.containsKey("options") ? params.options : [:], 'tbprofiler')
options.args = [
    params.call_whole_genome ? "--call_whole_genome" : "",
    params.calling_params ? "--calling_params ${params.calling_params}" : "",
    params.suspect ? "--suspect" : "",
    params.no_flagstat ? "--no_flagstat" : "",
    params.no_delly ? "--no_delly" : "",
    "--mapper ${params.mapper}",
    "--caller ${params.caller}",
    params.tbprofiler_opts ? "${params.calling_params}" : "",
].join(' ').replaceAll("\\s{2,}", " ").trim()

include { TBPROFILER_PROFILE as TBPROFILER_MODULE }  from '../../../modules/nf-core/tbprofiler/profile/main' addParams( options: options )

workflow TBPROFILER {
    take:
    reads // channel: [ val(meta), [ reads ] ]

    main:
    ch_versions = Channel.empty()

    TBPROFILER_MODULE(reads)
    ch_versions = ch_versions.mix(TBPROFILER_MODULE.out.versions)

    emit:
    bam = TBPROFILER_MODULE.out.bam
    csv = TBPROFILER_MODULE.out.csv
    json = TBPROFILER_MODULE.out.json
    txt = TBPROFILER_MODULE.out.txt
    vcf = TBPROFILER_MODULE.out.vcf
    versions = ch_versions // channel: [ versions.yml ]
}
