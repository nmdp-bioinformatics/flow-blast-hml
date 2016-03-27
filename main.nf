#!/usr/bin/env nextflow

params.hml           = "${baseDir}/tutorial/ex00_ngsp_expected.xml"
params.output        = "${baseDir}/tutorial/output"
params.imgtdir       = file("/opt/imgt")
params.imgt          = "3200"
params.report        = 1

imgtdb               = "${params.imgtdir}/${params.imgt}"
report               = "${params.report}"
outputDir            = file("${params.output}")
expectedFile         = file("${params.hml}")

outputDir.mkdirs()
expectedFile.copyTo("$outputDir/ex11_ngsp_expected.xml")

//Determining what operating system it's being run on
x   = System.properties['os.name']
catzip = '' 
if( x == "Mac OS X"){
  catzip = "gzcat"
}else{
  catzip = "zcat"
}

// Filtering out the failed subjects
process filterExpectedHml{

  input:
    set file(expected) from file("${params.hml}")

  output:
    set file(expected), file('*.gz') into fastqFiles mode flatten

  """
    ngs-extract-consensus -i ${expected}
  """
}

subjectIdFiles = fastqFiles.map{ hml, fileIn ->
  tuple(subjectId(fileIn), fileIn, hml ) 
}


//Blasting the consensus sequences
process blastn{
  tag{ subject }

  input:
    set subject, file(subjectFastq), file(hmlFailed) from subjectIdFiles
    set catType from catzip

  output:
    set subject, file {"${subject}.failed.txt"}  into blastObservedFile mode flatten
    set file {"${subject}.failed.txt"}  into finalFailedObserved mode flatten
    set subject, file{"${hmlFailed}"} into failedHmlFiles

  """
    $catzip ${subjectFastq} | blastn -db $imgtdb -outfmt 6 -query - > blast.out
    ngs-extract-blast -i blast.out -f ${subjectFastq} > ${subject}.failed.txt
  """
}

blastObservedSubjects = blastObservedFile
.collectFile() { subject, blast ->
       [ "${subject}.txt", blast.text ]
   }
.map{ path ->
  tuple( path, blastSubjectId(path), path) 
} 

finalFailedObserved
.collectFile() {  blast ->
       [ "ex11_ngsp_observed.txt", blast.text ]
   }
.subscribe { file -> copyToFailedDir(file) }


failedSubjects = blastObservedSubjects 
.map{ observed ->
  [observed[0], observed[1]]
}

//Validating the blast results
process validateInterpretation {
  tag{ subject }

  input:
    set file(observed), subject from failedSubjects
    set file(expected) from file("${params.hml}")

  output:
    set  file("${subject}_validate.txt") into failedValidated
    stdout inputDir

  """
    ngs-extract-expected-haploids -i ${expected} | ngs-validate-interpretation -b ${observed}  > ${subject}_validate.txt
    echo $outputDir
  """

}

failedValidatedFiles = failedValidated
.collectFile() { validated ->
       [ "ex11_ngsp_validated.txt", validated.text ]
   }
failedValidatedFiles.subscribe { file -> copyToFailedDir(file) }
reportInputFile = inputDir.toList()

//Generating the report if the reportFlag == 1
process generateReport {
  
  maxForks 1

  input:
    set infiles from reportInputFile
    val reportFlag from report

  when:
    reportFlag == '1'

  script:
  """
    ngs-validation-report -i blastnReport -f -v 1 -p $outputDir -d $infiles
  """ 

}


def copyToFailedDir (file) { 
  log.info "Copying ${file.name} into: $outputDir"
  file.copyTo(outputDir)
}

def subjectId(Path path) {
  def name = path.getFileName().toString()
  loc = name =~ /(\d{4}-\d{4}-\d{1})_\d{1,2}_\d{1,2}.fa.gz$/
  return loc[0][1]
}

def blastSubjectId(Path path) {
  def name = path.getFileName().toString()
  loc = name =~ /(\d{1,4}-\d{1,4}-\d{1}).txt$/
  return loc[0][1]
}








