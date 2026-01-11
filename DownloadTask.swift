mutating func fail(with message: String) {
      self.status = .failed
      self.errorMessage = message
      self.resumeDataPath = nil
  }