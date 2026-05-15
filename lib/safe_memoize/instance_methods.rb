# frozen_string_literal: true

module SafeMemoize
  module InstanceMethods
    include PublicMethods
    include CacheStoreMethods
    include CacheRecordMethods
    include InspectionMethods
    include HooksMethods
    include CacheMetricsMethods
    include PublicMetricsMethods
    include CustomKeyMethods
    include PublicCustomKeyMethods
    include LruMethods
  end
end
