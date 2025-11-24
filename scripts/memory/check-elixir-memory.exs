#!/usr/bin/env elixir

# Check Elixir VM memory stats
# Usage: elixir scripts/check-elixir-memory.exs

IO.puts("\n🔍 Elixir VM Memory Analysis\n")

# Memory breakdown
memory = :erlang.memory()

IO.puts("📊 Memory Usage:")
IO.puts("   Total:     #{div(memory[:total], 1024 * 1024)} MB")
IO.puts("   Processes: #{div(memory[:processes], 1024 * 1024)} MB")
IO.puts("   System:    #{div(memory[:system], 1024 * 1024)} MB")
IO.puts("   Atom:      #{div(memory[:atom], 1024 * 1024)} MB")
IO.puts("   Binary:    #{div(memory[:binary], 1024 * 1024)} MB")
IO.puts("   Code:      #{div(memory[:code], 1024 * 1024)} MB")
IO.puts("   ETS:       #{div(memory[:ets], 1024 * 1024)} MB")

IO.puts("\n⚛️  Atom Table:")
atom_count = :erlang.system_info(:atom_count)
atom_limit = :erlang.system_info(:atom_limit)
atom_percentage = Float.round(atom_count / atom_limit * 100, 2)

IO.puts("   Count:     #{atom_count}")
IO.puts("   Limit:     #{atom_limit}")
IO.puts("   Used:      #{atom_percentage}%")

if atom_percentage > 80 do
  IO.puts("   ⚠️  WARNING: Atom usage > 80% - potential leak!")
else
  IO.puts("   ✅ Atom usage healthy")
end

IO.puts("\n🧵 Process Count:")
process_count = :erlang.system_info(:process_count)
process_limit = :erlang.system_info(:process_limit)
process_percentage = Float.round(process_count / process_limit * 100, 2)

IO.puts("   Count:     #{process_count}")
IO.puts("   Limit:     #{process_limit}")
IO.puts("   Used:      #{process_percentage}%")

IO.puts("\n🔥 Top 10 Memory Consuming Processes:\n")

Process.list()
|> Enum.map(fn pid ->
  info = Process.info(pid, [:memory, :registered_name, :initial_call])
  {pid, info[:memory] || 0, info[:registered_name] || :unnamed, info[:initial_call]}
end)
|> Enum.sort_by(fn {_pid, memory, _name, _call} -> -memory end)
|> Enum.take(10)
|> Enum.with_index(1)
|> Enum.each(fn {{pid, memory, name, initial_call}, index} ->
  memory_mb = Float.round(memory / 1024 / 1024, 2)
  name_str = if name != :unnamed, do: "#{name}", else: "unnamed"
  {mod, fun, arity} = initial_call || {:unknown, :unknown, 0}
  IO.puts("   #{index}. #{memory_mb} MB - #{name_str} (#{inspect(pid)}) - #{mod}.#{fun}/#{arity}")
end)

IO.puts("")
