class DailySiteReportMeta {
  final String dailyLogId;
  final String? reportNo;
  final String? shift;
  final String? progressQuantity;
  final String? progressUnit;
  final double? percentComplete;
  final String? qualityInspections;
  final String? hseObservations;
  final String? siteInstructions;
  final String? nextDayPlan;
  final String? documentReferences;
  final String? preparedBy;
  final String? preparedByPosition;
  final String? reviewedBy;
  final String? approvedBy;
  final String? preparedSignaturePath;
  final String? reviewedSignaturePath;
  final String? approvedSignaturePath;

  const DailySiteReportMeta({
    required this.dailyLogId,
    this.reportNo,
    this.shift,
    this.progressQuantity,
    this.progressUnit,
    this.percentComplete,
    this.qualityInspections,
    this.hseObservations,
    this.siteInstructions,
    this.nextDayPlan,
    this.documentReferences,
    this.preparedBy,
    this.preparedByPosition,
    this.reviewedBy,
    this.approvedBy,
    this.preparedSignaturePath,
    this.reviewedSignaturePath,
    this.approvedSignaturePath,
  });

  Map<String, dynamic> toMap() => {
    'daily_log_id': dailyLogId,
    'report_no': reportNo,
    'shift': shift,
    'progress_quantity': progressQuantity,
    'progress_unit': progressUnit,
    'percent_complete': percentComplete,
    'quality_inspections': qualityInspections,
    'hse_observations': hseObservations,
    'site_instructions': siteInstructions,
    'next_day_plan': nextDayPlan,
    'document_references': documentReferences,
    'prepared_by': preparedBy,
    'prepared_by_position': preparedByPosition,
    'reviewed_by': reviewedBy,
    'approved_by': approvedBy,
    'prepared_signature_path': preparedSignaturePath,
    'reviewed_signature_path': reviewedSignaturePath,
    'approved_signature_path': approvedSignaturePath,
  };

  factory DailySiteReportMeta.fromMap(Map<String, dynamic> map) =>
      DailySiteReportMeta(
        dailyLogId: map['daily_log_id'] as String,
        reportNo: map['report_no'] as String?,
        shift: map['shift'] as String?,
        progressQuantity: map['progress_quantity'] as String?,
        progressUnit: map['progress_unit'] as String?,
        percentComplete: map['percent_complete'] == null
            ? null
            : (map['percent_complete'] as num).toDouble(),
        qualityInspections: map['quality_inspections'] as String?,
        hseObservations: map['hse_observations'] as String?,
        siteInstructions: map['site_instructions'] as String?,
        nextDayPlan: map['next_day_plan'] as String?,
        documentReferences: map['document_references'] as String?,
        preparedBy: map['prepared_by'] as String?,
        preparedByPosition: map['prepared_by_position'] as String?,
        reviewedBy: map['reviewed_by'] as String?,
        approvedBy: map['approved_by'] as String?,
        preparedSignaturePath: map['prepared_signature_path'] as String?,
        reviewedSignaturePath: map['reviewed_signature_path'] as String?,
        approvedSignaturePath: map['approved_signature_path'] as String?,
      );
}
