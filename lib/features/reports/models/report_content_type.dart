/// What kind of content a report targets — mirrors the `contentType` field
/// on `reports/{autoId}`.
enum ReportContentType { user, gig, message, review }

extension ReportContentTypeFirestore on ReportContentType {
  String get value {
    switch (this) {
      case ReportContentType.user:
        return 'user';
      case ReportContentType.gig:
        return 'gig';
      case ReportContentType.message:
        return 'message';
      case ReportContentType.review:
        return 'review';
    }
  }
}
