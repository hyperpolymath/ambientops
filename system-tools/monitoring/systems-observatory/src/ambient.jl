"""
    Ambient.jl - Ambient Computing Features for Juisys

    Implements Calm Technology principles through multi-modal feedback:
    - Visual (color-coding, GTK UI elements)
    - Audio (beeps for warnings)
    - IoT (MQTT notifications to smart home devices)

    Principles:
    - Glanceable: Information at-a-glance
    - Proportional: Alert intensity matches severity
    - Non-intrusive: Background awareness, not demanding attention

    PRIVACY: All feedback is local. MQTT is optional with consent.

    Author: Claude Sonnet 4.5 (Anthropic)
    License: MIT
"""

module Ambient

export AmbientMode, trigger_feedback, color_for_risk
export audio_alert, mqtt_notify
export create_visual_indicator, setup_ambient_environment

@enum AmbientMode VISUAL AUDIO IOT ALL NONE

"""
    color_for_risk(risk_level::String)

    Get color code for risk level following traffic light pattern.
    Returns RGB tuple.
"""
function color_for_risk(risk_level::String)
    risk_upper = uppercase(risk_level)

    colors = Dict(
        "NONE" => (0.2, 0.8, 0.2),       # Green
        "LOW" => (0.8, 0.8, 0.2),        # Yellow
        "MEDIUM" => (1.0, 0.6, 0.0),     # Orange
        "HIGH" => (1.0, 0.2, 0.2),       # Red
        "CRITICAL" => (0.8, 0.0, 0.8)    # Purple
    )

    return get(colors, risk_upper, (0.5, 0.5, 0.5))  # Gray default
end

"""
    trigger_feedback(risk_level::String, mode::AmbientMode;
                    message::String="Risk detected")

    Trigger appropriate ambient feedback for risk level.
    Implements Calm Technology proportional response.
"""
function trigger_feedback(risk_level::String, mode::AmbientMode;
                         message::String="Risk detected")

    if mode == NONE
        return
    end

    # Visual feedback
    if mode in [VISUAL, ALL]
        visual_feedback(risk_level, message)
    end

    # Audio feedback
    if mode in [AUDIO, ALL]
        audio_alert(risk_level)
    end

    # IoT feedback
    if mode in [IOT, ALL]
        mqtt_notify(risk_level, message)
    end
end

"""
    visual_feedback(risk_level::String, message::String)

    Display visual feedback (terminal colors or GTK if available).
"""
function visual_feedback(risk_level::String, message::String)
    color = color_for_risk(risk_level)

    # Terminal color codes
    color_code = if uppercase(risk_level) == "CRITICAL"
        "\e[35m"  # Magenta
    elseif uppercase(risk_level) == "HIGH"
        "\e[31m"  # Red
    elseif uppercase(risk_level) == "MEDIUM"
        "\e[33m"  # Yellow
    elseif uppercase(risk_level) == "LOW"
        "\e[32m"  # Green
    else
        "\e[32m"  # Green (NONE)
    end

    reset_code = "\e[0m"

    # Print colored message
    println("$(color_code)● $(uppercase(risk_level)): $message$(reset_code)")
end

"""
    audio_alert(risk_level::String)

    Play audio beep proportional to risk level.
    Requires system audio support (optional).
"""
function audio_alert(risk_level::String)
    # Number of beeps based on severity
    beep_count = if uppercase(risk_level) == "CRITICAL"
        3
    elseif uppercase(risk_level) == "HIGH"
        2
    elseif uppercase(risk_level) == "MEDIUM"
        1
    else
        0  # No beeps for low/none
    end

    for i in 1:beep_count
        try
            # Bell character (ASCII 7)
            print("\a")
            sleep(0.3)
        catch e
            @warn "Audio alert failed" exception=e
            break
        end
    end
end

"""
    mqtt_notify(risk_level::String, message::String;
               broker::String="localhost", port::Int=1883)

    Send notification to MQTT broker for IoT device integration.
    Requires IOT_PUBLISH consent and MQTT.jl package.

    PRIVACY: Only sends to LOCAL broker by default (no cloud).
"""
function mqtt_notify(risk_level::String, message::String;
                    broker::String="localhost", port::Int=1883)

    # Check if MQTT.jl is available
    if !isdefined(Main, :MQTT)
        @warn "MQTT.jl not available - IoT notifications disabled"
        return
    end

    # NOTE: In production, verify IOT_PUBLISH consent here

    try
        # This is placeholder - actual implementation would use MQTT.jl
        topic = "juisys/alerts/$(lowercase(risk_level))"

        payload = Dict(
            "risk_level" => risk_level,
            "message" => message,
            "timestamp" => string(now())
        )

        @info "MQTT notification" topic=topic broker=broker

        # Actual MQTT publish would happen here
        # client = MQTT.Client(broker, port)
        # MQTT.publish(client, topic, JSON3.write(payload))

    catch e
        @error "MQTT notification failed" exception=e
    end
end

"""
    create_visual_indicator(risk_level::String, width::Int=40)

    Create ASCII art visual indicator (progress bar style).
    Implements glanceable design principle.
"""
function create_visual_indicator(risk_level::String, width::Int=40)
    # Map risk to fill percentage
    fill_pct = if uppercase(risk_level) == "CRITICAL"
        1.0
    elseif uppercase(risk_level) == "HIGH"
        0.75
    elseif uppercase(risk_level) == "MEDIUM"
        0.5
    elseif uppercase(risk_level) == "LOW"
        0.25
    else
        0.0
    end

    filled = Int(round(width * fill_pct))
    empty = width - filled

    # Choose fill character based on risk
    fill_char = if fill_pct >= 0.75
        '█'
    elseif fill_pct >= 0.5
        '▓'
    elseif fill_pct >= 0.25
        '▒'
    else
        '░'
    end

    bar = repeat(fill_char, filled) * repeat(' ', empty)

    color_code = color_for_risk(risk_level)

    return "[$(bar)]"
end

"""
    setup_ambient_environment()

    Setup ambient computing environment.
    Detects available capabilities (GTK, audio, MQTT).

    Returns: Available AmbientMode
"""
function setup_ambient_environment()
    available_modes = []

    # Check for GTK
    if isdefined(Main, :Gtk)
        push!(available_modes, VISUAL)
        @info "GTK available for visual feedback"
    else
        push!(available_modes, VISUAL)  # Terminal colors always available
    end

    # Check for audio
    # Audio via \a bell character is always available
    push!(available_modes, AUDIO)

    # Check for MQTT
    if isdefined(Main, :MQTT)
        push!(available_modes, IOT)
        @info "MQTT available for IoT notifications"
    end

    if length(available_modes) >= 3
        return ALL
    elseif VISUAL in available_modes
        return VISUAL  # Minimum viable mode
    else
        return NONE
    end
end

"""
    display_ambient_summary(results::Vector)

    Display color-coded summary of audit results.
    Glanceable overview using Calm Technology principles.
"""
function display_ambient_summary(results::Vector)
    println("\n" * "="^60)
    println("AMBIENT AUDIT SUMMARY")
    println("="^60)

    # Count by risk level
    risk_counts = Dict(
        "CRITICAL" => 0,
        "HIGH" => 0,
        "MEDIUM" => 0,
        "LOW" => 0,
        "NONE" => 0
    )

    for result in results
        risk = uppercase(get(result, :risk_level, "NONE"))
        if haskey(risk_counts, risk)
            risk_counts[risk] += 1
        end
    end

    # Display each risk level with visual indicator
    for (risk, count) in sort(collect(risk_counts), by=x->x[1], rev=true)
        if count > 0
            indicator = create_visual_indicator(risk, 20)
            visual_feedback(risk, "$count application(s)")
        end
    end

    println("="^60)
end

end # module Ambient
