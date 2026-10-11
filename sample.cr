def raise_in_method
  raise "from method"
end

def call_method
  raise_in_method
end

def print_backtrace(&)
  yield
rescue ex
  puts ex.backtrace.join('\n')
  puts
end

print_backtrace { call_method }

callback = -> { raise "from proc" }
print_backtrace { callback.call }
