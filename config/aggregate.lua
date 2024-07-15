function add_metrics(tag, timestamp, record)
    if not _G.metrics_cache then
        _G.metrics_cache = {}
    end

    -- Add the current metric to the cache
    table.insert(_G.metrics_cache, record)

    -- If we have collected enough metrics, flush them
    if #_G.metrics_cache >= 10 then
        local new_record = {}
        new_record["metrics_logs"] = _G.metrics_cache
        _G.metrics_cache = {}  -- Reset cache
        return 1, timestamp, new_record
    end

    -- Return nil to skip output
    return -1, timestamp, record
end
