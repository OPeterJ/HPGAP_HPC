package PopGenome_Combine_Calling;
use File::Basename;
use File::Path qw(make_path);
use strict;
use warnings;
use FindBin '$Bin';
use YAML::Tiny;
use lib "$Bin/lib";
use PopGenome_Shared;

#################################
#			   #
#    Step 1f Variant calling    #
#			   #
#################################
sub COMBINE_CALLING{

	my ($yml_file,$skipsh) = @_;
	my $yaml = YAML::Tiny->read( $yml_file );
	my %cfg = %{$yaml->[0]};

	my %samplelist = %{$cfg{fqdata}};

	my $reference = $cfg{ref}{db}{$cfg{ref}{choose}}{path};
	my $outpath = "$cfg{args}{outdir}/01.QualityControl/"; 
	if ( !-d $outpath ) {make_path $outpath or die "Failed to create path: $outpath";} 
	my $shpath = "$cfg{args}{outdir}/PipelineScripts/01.QualityControl/Combined";
	if ( !-d $shpath ) {make_path $shpath or die "Failed to create path: $shpath";}

	open CL, ">$shpath/cmd_combine_calling.list";

	open SH, ">$shpath/combine_calling.sh";
	## Joint genotyping
	## First, merge all the gvcf results, then perform GenotypeGVCFs
	my $sample_gvcfs = "";
	foreach my $sample (keys %samplelist){
		$sample_gvcfs .= "	-V $outpath/read_mapping.$cfg{ref}{choose}/$sample/$sample.HC.gvcf.gz \\\n";
	}
	print SH "#!/bin/sh\ncd $outpath\n";
	# Consider replace CombineGCVFs with GenomicsDBimport
	# Through CombineGVCFs or GenomicsDBimport, we gather all the per-sample GVCFs and pass them to GenotypeGVCFs, which produces a set of joint-called SNP and indel calls ready for fitlering.

	print SH "gatk CombineGVCFs \\\n";
	print SH "	-R $reference \\\n";
	print SH "$sample_gvcfs";
	print SH "	-O $outpath/Combined/Combined.HC.g.vcf.gz && echo \"** Combined.HC.g.vcf.gz done ** \"\n";

	print SH "gatk GenotypeGVCFs \\\n";
	print SH "	-R $reference \\\n";
	print SH "	-ploidy $cfg{args}{ploidy} \\\n";
	print SH "	-V $outpath/Combined/Combined.HC.g.vcf.gz \\\n";
	print SH "	-O $outpath/Combined/Combined.HC.vcf.gz && echo \"** Combined.HC.vcf.gz done ** \"\n";

	# The established way to filter the raw variant callset is to use variant quality score recalibration (VQSR), which uses machine learning to identify annotation profiles of variants that are likely to be real, and assigns a VQSLOD score to each variant that is much more reliable than the QUAL score calculated by the caller. In the first step of this two-step process, the program builds a model based on training variants, then applies that model to the data to assign a well-calibrated probability to each variant call.
	# We can then use this variant quality score in the second step to filter the raw call set, thus producing a subset of calls with our desired level of quality, fine-tuned to balance specificity and sensitivity.
	## SNP mode
	close SH;
	print CL "sh $shpath/combine_calling.sh 1>$shpath/combine_calling.sh.o 2>$shpath/combine_calling.sh.e\n";
	close CL;

	`perl $Bin/lib/qsub.pl -d $shpath/cmd_combine_calling_qsub -q $cfg{args}{queue} -P $cfg{args}{prj} -l 'vf=12G,num_proc=1 -binding linear:1' -m 100 -r $shpath/cmd_combine_calling.list` unless ($skipsh ==1);
}

1;