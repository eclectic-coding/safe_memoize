# frozen_string_literal: true


module SafeMemoize
  module InstanceMethods
    include PublicMethods
    include CacheStoreMethods
    include CacheRecordMethods
    include InspectionMethods
  end
end

