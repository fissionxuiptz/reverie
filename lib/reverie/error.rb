module Reverie
  class Error < StandardError
  end

  class UpdateFrequencyError < Error
  end

  class IPFetchError < Error
  end

  class InvalidRecordError < Error
  end

  class InvalidIP < Error
  end

  class ListRecordError < Error
  end

  class RecordNotEditable < Error
  end

  class AddRecordError < Error
  end
end
