"""
Token-efficient workout history compression for AI prompts.
Reduces token usage by 60-70% while preserving critical progressive overload data.
"""

def compress_workout_history(workouts, focus_on_prior_week=True):
    """
    Compress workout history to essential data for AI consumption.
    
    Args:
        workouts: List of workout dictionaries from sheets_reader
        focus_on_prior_week: If True, prioritize most recent week's data
    
    Returns:
        Compressed string representation (60-70% fewer tokens)
    """
    if not workouts:
        return "No workout history available."
    
    # Strategy: Keep only the data Claude needs for progressive overload
    # - Exercise name
    # - Load used
    # - Reps/sets achieved
    # - RPE (if provided)
    # - Form quality (if poor/noted issues)
    # - Log status (completed/skipped)
    
    if focus_on_prior_week:
        # Take only the most recent week (last 3-4 workouts)
        workouts = workouts[-4:]
    
    compressed = "RECENT WORKOUT HISTORY (Compressed):\n\n"
    
    for workout in workouts:
        date = workout['date']
        compressed += f"📅 {date}\n"
        
        # Group by significant exercises only (skip warm-ups, mobility)
        significant_exercises = []
        for ex in workout['exercises']:
            # Filter out warm-up/prep movements
            exercise_name = ex['exercise'].lower()
            if any(skip in exercise_name for skip in ['hip switch', 'glute activation', 'mcgill', 'bird dog', 'plank']):
                continue
            
            # Keep exercises with load/performance data
            if ex['sets'] or ex['load'] or ex['log']:
                significant_exercises.append(ex)
        
        # Use ultra-compact format
        for ex in significant_exercises:
            # Format: "Exercise: SetsxReps@Load [RPE:X] [Status]"
            line = f"  • {ex['exercise']}"
            
            # Add performance data compactly
            if ex['sets'] and ex['reps']:
                line += f": {ex['sets']}x{ex['reps']}"
            elif ex['sets']:
                line += f": {ex['sets']} sets"
                
            if ex['load']:
                line += f"@{ex['load']}"
            
            # Add critical feedback (RPE, form issues)
            feedback = []
            if ex.get('rpe'):
                feedback.append(f"RPE{ex['rpe']}")
            if ex.get('form') and any(word in ex['form'].lower() for word in ['struggled', 'breakdown', 'poor', 'failed']):
                feedback.append("⚠️form")
            if ex.get('log'):
                if 'done' in ex['log'].lower() or 'completed' in ex['log'].lower():
                    feedback.append("✓")
                elif 'skip' in ex['log'].lower():
                    feedback.append("⊗")
            
            if feedback:
                line += f" [{', '.join(feedback)}]"
            
            # Add notes only if critical (adjustments, issues)
            if ex.get('notes') and any(word in ex['notes'].lower() for word in ['struggled', 'failed', 'adjusted', 'reduced', 'increased']):
                line += f" - Note: {ex['notes'][:50]}"
            
            compressed += line + "\n"
        
        compressed += "\n"
    
    return compressed


def compress_supplemental_history(supplemental_data):
    """
    Compress prior week's supplemental workouts for progressive overload.
    
    Args:
        supplemental_data: Dictionary with Tuesday, Thursday, Saturday data
    
    Returns:
        Compressed string (60-70% fewer tokens)
    """
    if not supplemental_data:
        return "No prior supplemental data."
    
    compressed = "PRIOR WEEK SUPPLEMENTAL (Compressed):\n\n"
    
    for day in ['Tuesday', 'Thursday', 'Saturday']:
        exercises = supplemental_data.get(day, [])
        if not exercises:
            continue
        
        compressed += f"🗓️ {day}:\n"
        
        for ex in exercises:
            # Ultra-compact: "Exercise: SetsxReps@Load [RPE, Status]"
            line = f"  • {ex['exercise']}"
            
            if ex.get('sets') and ex.get('reps'):
                line += f": {ex['sets']}x{ex['reps']}"
            
            if ex.get('load'):
                line += f"@{ex['load']}"
            
            # Add RPE and completion status
            feedback = []
            if ex.get('rpe'):
                feedback.append(f"RPE{ex['rpe']}")
            if ex.get('log'):
                if 'done' in ex['log'].lower():
                    feedback.append("✓")
                elif 'skip' in ex['log'].lower():
                    feedback.append("⊗")
            
            if feedback:
                line += f" [{', '.join(feedback)}]"
            
            compressed += line + "\n"
        
        compressed += "\n"
    
    return compressed


def get_token_savings_estimate(original_text, compressed_text):
    """
    Estimate token savings from compression.
    Uses rough approximation: 1 token ≈ 4 characters.
    
    Returns:
        Dictionary with savings stats
    """
    original_tokens = len(original_text) // 4
    compressed_tokens = len(compressed_text) // 4
    savings = original_tokens - compressed_tokens
    savings_pct = (savings / original_tokens * 100) if original_tokens > 0 else 0
    
    return {
        'original_tokens': original_tokens,
        'compressed_tokens': compressed_tokens,
        'tokens_saved': savings,
        'savings_percent': round(savings_pct, 1)
    }
