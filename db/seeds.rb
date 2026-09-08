# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).


# Seed Roles (idempotent)
roles = {
  "guest" => "Unauthenticated/public visitor",
  "player" => "Registered beach volleyball player",
  "coach" => "Registered coach who can manage content",
  "admin" => "System administrator"
}

roles.each do |name, description|
  Role.find_or_create_by!(name: name) do |role|
    role.description = description
  end
end

puts "Seeded #{Role.count} roles"
# Seed Categories
categories = ["Attack", "Block", "Defence", "Serve", "Reception", "Strategy", "Tactics", "Set"]

categories.each do |category_name|
  Category.find_or_create_by!(name: category_name)
end

puts "Seeded #{Category.count} categories"

# Seed Skills with Descriptions from Beach Volleyball Coaching Curriculum
skills_data = {
  "Strategy" => [
    { title: "Which side to choose", description: "Analyze opponent positioning and movement patterns to determine optimal serving targets. Consider their weaker side, footwork speed, and court coverage tendencies." },
    { title: "When start receiving or serving", description: "Understand the optimal timing to begin your approach movement based on the ball trajectory and your position on the court. Anticipate early to maximize preparation time." },
    { title: "Who to serve on. When serve middle.", description: "Identify which opponent to target with serves based on their reception skills. Serving to the middle can create confusion about who should take the ball." },
    { title: "When ask for time out", description: "Recognize situations that warrant a timeout: when losing momentum, when opponent has a scoring run, or when players need to reset mentally. Maximum 1 per set in beach volleyball." },
    { title: "How to use the wind and sun in your favor", description: "Adapt your strategy based on environmental conditions. Use wind direction for float serves, position yourself to avoid sun glare, and adjust shot selection accordingly." },
    { title: "When short/long", description: "Decide when to play short shots versus deep shots based on opponent positioning. Short shots exploit open court behind blockers, long shots push opponents back." },
    { title: "When do seconds", description: "Know when to attack on the second ball instead of setting. This surprise tactic can catch opponents off guard when they expect a standard set-attack pattern." },
    { title: "Always play close", description: "Maintain compact court positioning with your partner. Being close together reduces gaps in coverage and allows for better communication and transition play." },
    { title: "Always talk. What to talk. Who talks", description: "Maintain constant verbal communication about ball coverage, opponent positioning, and play calls. The player behind the ball typically directs the play." },
    { title: "Priority on the right or left", description: "Determine which side of the court to prioritize based on your strengths and opponent weaknesses. Establish clear coverage responsibilities for each side." },
    { title: "Who is middle", description: "Clarify which player covers the middle of the court in different situations. Clear middle coverage assignments prevent balls from dropping between players." },
    { title: "Court position (always close to each other)", description: "Maintain optimal spacing between partners based on game situation. Closer for defense, slightly wider for coverage, always within communication range." },
    { title: "Read other players body", description: "Observe opponent body language, foot positioning, and arm movements to anticipate their next play. Early reading provides crucial reaction time advantages." },
    { title: "Position to serve receive", description: "Establish optimal serve receive positioning based on server tendencies, wind conditions, and your team strengths. Balance court coverage with attacking preparation." }
  ],
  "Defence" => [
    { title: "Behind the ball", description: "Position yourself directly behind the ball trajectory to create a stable platform for controlled defensive plays. This alignment maximizes your field of vision and reaction time." },
    { title: "Lateral/shoulder", description: "Execute lateral defensive movements using proper shoulder rotation and hip alignment. Move sideways efficiently while maintaining balance and readiness to react." },
    { title: "Lateral high", description: "Defend high balls coming from the side using extended reach and proper body positioning. Use your arms at maximum height while maintaining body control." },
    { title: "Lateral moving", description: "Move laterally while maintaining defensive stance and court awareness. Shuffle steps and crossover techniques for efficient side-to-side coverage." },
    { title: "Behind normal", description: "Position yourself in the standard defensive spot behind the expected hit trajectory. This default position optimizes your ability to react to various shot types." },
    { title: "Behind with scoop", description: "Use a scooping motion when defending balls that drop short or require reaching below waist level. Keep arms together and use legs for upward momentum." },
    { title: "Front short, both arms", description: "Defend short balls at the net using both arms extended forward. Quick reaction and soft hands are essential for controlled digs on sharp angle shots." },
    { title: "Front short, one arm", description: "Use single-arm digs for balls that require extended reach at the net. This technique covers more court area but requires precise timing and control." },
    { title: "Tomahawk", description: "Execute the tomahawk defensive technique for hard-driven balls at close range. Use overhead arm motion to redirect balls upward when traditional digs are not possible." },
    { title: "Poke", description: "Use finger poke technique for soft defensive plays on short balls. Requires precise finger strength and touch to control ball direction and height." },
    { title: "Transition to attack", description: "Quickly move from defensive positioning to attacking readiness after a successful dig. Anticipate the set and prepare for your hitting approach." },
    { title: "Opposite from block", description: "Position yourself opposite to where your partner is blocking. This creates optimal court coverage and reduces defensive gaps." },
    { title: "Saving hard driven hit - dig", description: "Use low, stable platform technique to absorb and redirect hard-driven attacks. Focus on cushioning the ball with arms while maintaining body control." },
    { title: "Saving hard driven hit - high", description: "Defend hard-driven balls that travel at chest height or above. Use hands positioned up with soft touch to redirect balls to target." },
    { title: "Gator", description: "Use the gator technique for balls that require digging with hands together and rolling motion. Effective for hard-driven balls at close range." },
    { title: "Saving after ball on the net", description: "Recover and play balls that hit the net and drop on your side. Quick reflexes and anticipation are key for these unpredictable bounces." }
  ],
  "Set" => [
    { title: "Dig", description: "Execute a setting motion starting from a dig position. This technique combines defensive reception with setting accuracy in one fluid motion." },
    { title: "Handset", description: "Perform overhead setting using proper hand positioning with fingers spread and thumbs pointing toward face. Control ball trajectory through fingertip contact and extension." },
    { title: "Back set", description: "Direct the set behind the setter toward the right-side attacker. Requires proper body rotation, arm extension, and consistent release point for accuracy." },
    { title: "From back of the court", description: "Execute sets from deep court positions. Requires stronger arm action and higher arc to give attackers time to approach and hit effectively." },
    { title: "Knees on the sand", description: "Set from a kneeling position when necessary for low balls or emergency situations. Maintain hand position while generating power from arm extension." },
    { title: "Foot work", description: "Use proper footwork to get behind the ball quickly and efficiently. Small adjustment steps and shuffle patterns optimize setting position and balance." },
    { title: "Set with wind", description: "Adjust setting technique to compensate for wind conditions. Modify arc, speed, and contact point based on wind direction and strength." },
    { title: "Short set", description: "Deliver a quick, low set close to the net for fast attacks. Requires precise timing with the hitter and minimal ball travel time." },
    { title: "Back set in emergency", description: "Execute back sets under pressure or from difficult positions. Essential skill for when forward sets are not possible due to ball trajectory or position." }
  ],
  "Attack" => [
    { title: "Nike position", description: "Adopt the hitting position with arms extended overhead resembling the Nike logo. This ready position allows for quick arm swing initiation and maximum reach." },
    { title: "Rotation of arms and body", description: "Generate hitting power through coordinated body rotation. Start from hips, transfer through torso, and finish with arm whip for maximum velocity." },
    { title: "Position on the right", description: "Establish optimal hitting position on the right side of the court. Adjust approach angle and timing based on set location and blocker position." },
    { title: "Position on the left", description: "Establish optimal hitting position on the left side of the court. Mirror right-side techniques while accounting for different approach angles." },
    { title: "Steps to hit", description: "Execute the proper 3-step or 4-step approach for hitting. Left-right-left for right-handed hitters, building momentum and timing with the set." },
    { title: "Cross", description: "Hit the ball diagonally across the court to the opposite corner. Effective for avoiding blockers and exploiting open court areas." },
    { title: "High line", description: "Hit the ball down the line with high trajectory. This shot goes over the block and lands deep in the court near the sideline." },
    { title: "Short cut", description: "Execute a sharp angle shot that lands short and inside the block. Requires wrist snap and precise hand control to cut the ball at extreme angles." },
    { title: "Drop shot", description: "Use a soft touch shot that drops just over the block into open court. Deceptive technique that catches defenders off guard when they expect a hard hit." },
    { title: "Rainbow", description: "Hit the ball with extreme arc that goes high over the block and drops steeply into the back court. Effective against tight net coverage." },
    { title: "Poke", description: "Use finger tip contact to softly place the ball over the block into open areas. Requires excellent touch and timing for controlled placement." },
    { title: "Challenge the block", description: "Intentionally hit into the block to create deflections or tool the block. Aim for the outside hand to redirect balls out of bounds off the blocker." },
    { title: "Fake the moves", description: "Use deceptive body movements and arm actions to misdirect blockers. Show one shot direction then execute another to create hitting lanes." },
    { title: "Short set", description: "Hit quick sets that travel minimal distance from setter. Requires fast approach timing and compact swing for effective execution." },
    { title: "Hit on second", description: "Attack the ball on the second contact instead of setting. Surprise tactic that catches opponents before they can set up their block." },
    { title: "Ball too close to the net", description: "Handle sets that are tight to the net. Use open hand technique to push or roll the ball over while avoiding net violations." }
  ],
  "Block" => [
    { title: "Signs", description: "Communicate blocking intentions and coverage with partner through hand signals behind the back. Signals indicate line, cross, or peel coverage." },
    { title: "Foot work", description: "Use proper footwork for blocking approach and lateral movement. Shuffle steps and crossover techniques to position at the net efficiently." },
    { title: "Peel - Hard driven", description: "Step away from the net to defend hard-driven balls that go past the block. Quick reaction and transition from blocking to defensive stance." },
    { title: "Peel - Short", description: "Move off the net to cover short shots and drops that fall just over the block. Requires reading the hitter early and quick first step." },
    { title: "Peel - Long", description: "Transition from blocking position to defend deep shots that go over the block. Backpedal and get behind the ball for controlled defensive play." },
    { title: "Block line", description: "Position the block to cover the line shot, forcing the hitter to go cross-court. Outside hand aligns with the sideline to seal off the angle." },
    { title: "Block cross", description: "Position the block to cover cross-court shots, forcing the hitter down the line. Inside hand covers the middle, outside hand seals the cross-court angle." },
    { title: "Serve and go to block", description: "Transition from serving to blocking position immediately after contact. Quick movement up to the net to establish the block against the return." },
    { title: "Ball in the back after block", description: "Defend balls that deflect off the block into the back court. Read the deflection angle and position for controlled defensive play." },
    { title: "How to turn after block", description: "Execute proper body rotation after landing from a block to prepare for the next play. Quick transition from blocking stance to defensive or attacking readiness." }
  ],
  "Serve" => [
    { title: "Position of serve wind/sun", description: "Adjust serving position based on wind direction and sun location. Use wind at your back for power, avoid serving into the sun, and account for drift." },
    { title: "Arm swing", description: "Execute proper serving arm motion with high elbow, full extension, and wrist snap. Generate power from shoulder rotation and follow through toward target." },
    { title: "Short", description: "Execute a serve that lands just over the net in the front court. Forces receivers to move forward quickly and can disrupt their attacking rhythm." },
    { title: "Long", description: "Serve deep to the back of the court to push receivers away from the net. Creates difficulty for quick attacks and can force free balls back." },
    { title: "Direction", description: "Control serve placement to target specific court areas. Aim for weak receivers, seams between players, or corners to maximize serving effectiveness." },
    { title: "Jump float", description: "Execute a jump serve with minimal spin for unpredictable ball movement. The floating action makes it difficult for receivers to judge trajectory." },
    { title: "Jump serve", description: "Perform an aggressive jump serve with topspin for power and downward trajectory. Requires precise timing, approach, and contact point for consistency." }
  ]
}

skills_data.each do |category_name, skills|
  category = Category.find_by!(name: category_name)
  skills.each do |skill_data|
    skill = Skill.find_or_create_by!(title: skill_data[:title], category: category)
    skill.update!(description: skill_data[:description])
  end
end

puts "Seeded #{Skill.count} skills with descriptions"

# Seed Drills
drills_data = [
  # Strategy Drills
  { title: "Target Serving Analysis", setup_instructions: "Place targets in each corner of the court. Server practices identifying and serving to the weakest receiver. Partners provide feedback on target selection.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Which side to choose", "Who to serve on. When serve middle."] },
  { title: "Court Positioning Drill", setup_instructions: "Coach calls out game situations. Players must quickly move to correct court positions and communicate coverage. Emphasize staying close together.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Court position (always close to each other)", "Who is middle"] },
  { title: "Communication Practice", setup_instructions: "During practice rallies, players must call out every play loudly. Coach evaluates quality and timing of verbal cues between partners.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Always talk. What to talk. Who talks"] },
  { title: "Wind Reading Exercise", setup_instructions: "Practice serving and hitting with attention to wind direction. Adjust technique based on conditions and discuss strategy adaptations between plays.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["How to use the wind and sun in your favor"] },
  { title: "Serve Receive Positioning", setup_instructions: "Server serves from various positions. Receiver adjusts starting position based on server tendencies and practices optimal platform angle.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Position to serve receive"] },
  # Defence Drills
  { title: "Lateral Movement Defence", setup_instructions: "Coach hits balls to alternating sides. Defender practices lateral shuffle and shoulder rotation to get behind each ball with proper platform.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Lateral/shoulder", "Lateral moving"] },
  { title: "High Ball Defence", setup_instructions: "Coach hits high arcing balls from the opposite end. Defender practices positioning behind the ball and using controlled platform for accurate digs.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Behind the ball", "Lateral high"] },
  { title: "Tomahawk Practice", setup_instructions: "Coach hits hard-driven balls at close range. Defender practices overhead tomahawk technique for emergency defensive plays.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Tomahawk"] },
  { title: "Transition Attack Drill", setup_instructions: "Defender digs a controlled ball, then immediately transitions to attacking position. Setter sets to transitioning player for immediate attack.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Transition to attack"] },
  { title: "Hard Driven Ball Dig", setup_instructions: "Attacker hits hard-driven balls at defender. Defender practices low platform technique and body control to absorb pace and redirect to target.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Saving hard driven hit - dig", "Saving hard driven hit - high"] },
  { title: "Gator Technique Drill", setup_instructions: "Coach hits hard balls at close range. Defender practices gator dig with hands together and rolling motion for controlled upward redirection.", player_count: 2, difficulty_level: "advanced", skill_titles: ["Gator"] },
  { title: "Net Ball Recovery", setup_instructions: "Coach tips balls into the net from various angles. Defender practices quick reaction to unpredictable bounces and recovery plays.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Saving after ball on the net"] },
  # Set Drills
  { title: "Wall Setting Repetitions", setup_instructions: "Player sets against a wall at varying distances. Focus on hand position, finger spread, and consistent contact point for accuracy.", player_count: 1, difficulty_level: "beginner", skill_titles: ["Handset", "Foot work"] },
  { title: "Back Set Practice", setup_instructions: "Setter practices back sets to a target behind them. Focus on body rotation, arm extension, and consistent release point for accuracy.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Back set"] },
  { title: "Deep Court Setting", setup_instructions: "Setter positioned deep in court practices setting to attackers. Focus on higher arc and stronger arm action to create effective attack opportunities.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["From back of the court"] },
  { title: "Short Set Timing", setup_instructions: "Setter and hitter practice quick combination plays. Focus on minimal ball travel time and precise timing for fast attacks.", player_count: 2, difficulty_level: "advanced", skill_titles: ["Short set"] },
  { title: "Emergency Back Set", setup_instructions: "Coach feeds difficult balls that require back setting. Setter practices technique under pressure for emergency back set situations.", player_count: 2, difficulty_level: "advanced", skill_titles: ["Back set in emergency"] },
  { title: "Wind Setting Adjustment", setup_instructions: "Practice setting in windy conditions. Adjust arc, speed, and contact point to compensate for wind effects on ball trajectory.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Set with wind"] },
  # Attack Drills
  { title: "Approach and Hit Timing", setup_instructions: "Practice the 3-step approach with proper timing to the set. Focus on building momentum and connecting with the ball at peak height.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Steps to hit", "Nike position"] },
  { title: "Cross Court Hitting", setup_instructions: "Setter sets to attacker who practices hitting diagonally across court. Focus on arm angle and wrist control for accurate placement.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Cross", "Rotation of arms and body"] },
  { title: "Line Shot Practice", setup_instructions: "Attacker practices hitting down the line with high trajectory. Focus on going over the block and landing deep near the sideline.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["High line"] },
  { title: "Cut Shot Technique", setup_instructions: "Attacker practices short cut shots at sharp angles. Focus on wrist snap and hand control to cut the ball at extreme angles.", player_count: 2, difficulty_level: "advanced", skill_titles: ["Short cut"] },
  { title: "Drop Shot Deception", setup_instructions: "Attacker shows full hitting motion then executes soft drop shot. Focus on deception and touch to place ball just over the block.", player_count: 2, difficulty_level: "advanced", skill_titles: ["Drop shot"] },
  { title: "Block Tooling Drill", setup_instructions: "With a blocker at net, attacker practices hitting off the outside hand. Aim for deflections out of bounds off the blocker.", player_count: 3, difficulty_level: "advanced", skill_titles: ["Challenge the block"] },
  { title: "Quick Set Attack", setup_instructions: "Setter delivers short sets for immediate attack. Hitter practices fast approach timing and compact swing for quick combination plays.", player_count: 2, difficulty_level: "advanced", skill_titles: ["Short set", "Hit on second"] },
  { title: "Tight Net Ball Handling", setup_instructions: "Setter delivers sets tight to the net. Attacker practices open hand technique to push or roll balls over while avoiding net violations.", player_count: 2, difficulty_level: "advanced", skill_titles: ["Ball too close to the net"] },
  # Block Drills
  { title: "Block Communication Signals", setup_instructions: "Practice hand signals behind the back to indicate blocking coverage. Partners must read signals and position accordingly before each play.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Signs"] },
  { title: "Block Footwork Patterns", setup_instructions: "Practice lateral movement along the net for blocking. Focus on shuffle steps and crossover techniques to position efficiently.", player_count: 2, difficulty_level: "beginner", skill_titles: ["Foot work"] },
  { title: "Peel and Defence Transition", setup_instructions: "Blocker practices stepping away from net to defend various shot types. Quick transition from blocking to defensive stance for short and deep balls.", player_count: 3, difficulty_level: "intermediate", skill_titles: ["Peel - Short", "Peel - Long", "Peel - Hard driven"] },
  { title: "Line Block Positioning", setup_instructions: "Practice setting the block to cover the line shot. Outside hand aligns with sideline to seal off the angle and force cross-court.", player_count: 3, difficulty_level: "intermediate", skill_titles: ["Block line"] },
  { title: "Cross Court Block Setup", setup_instructions: "Position the block to cover cross-court shots. Inside hand covers middle, outside hand seals the cross-court angle to force line shots.", player_count: 3, difficulty_level: "intermediate", skill_titles: ["Block cross"] },
  { title: "Serve and Block Transition", setup_instructions: "Server immediately transitions to blocking position after serving. Practice quick movement up to net to establish block against the return.", player_count: 2, difficulty_level: "intermediate", skill_titles: ["Serve and go to block"] },
  { title: "Block Landing and Turn", setup_instructions: "Practice proper landing technique after blocking and quick body rotation. Transition from blocking stance to defensive or attacking readiness.", player_count: 2, difficulty_level: "beginner", skill_titles: ["How to turn after block"] },
  # Serve Drills
  { title: "Target Serving", setup_instructions: "Place targets in various court locations. Server practices hitting specific zones with consistency. Track success rate for each target area.", player_count: 1, difficulty_level: "beginner", skill_titles: ["Direction", "Short", "Long"] },
  { title: "Jump Float Serve Practice", setup_instructions: "Practice jump float serve technique focusing on minimal spin and unpredictable ball movement. Aim for consistent contact point and float action.", player_count: 1, difficulty_level: "intermediate", skill_titles: ["Jump float", "Arm swing"] },
  { title: "Jump Serve Power", setup_instructions: "Execute aggressive jump serves with topskin for power and downward trajectory. Focus on approach timing, contact point, and follow through.", player_count: 1, difficulty_level: "advanced", skill_titles: ["Jump serve", "Arm swing"] },
  { title: "Environmental Serving", setup_instructions: "Practice serving with attention to wind and sun conditions. Adjust position and technique based on environmental factors for optimal results.", player_count: 1, difficulty_level: "intermediate", skill_titles: ["Position of serve wind/sun"] },
]

drills_data.each do |drill_data|
  skill_titles = drill_data.delete(:skill_titles)
  drill = Drill.find_or_create_by!(title: drill_data[:title]) do |d|
    d.setup_instructions = drill_data[:setup_instructions]
    d.player_count = drill_data[:player_count]
    d.difficulty_level = drill_data[:difficulty_level]
  end
  
  skill_titles.each do |skill_title|
    skill = Skill.find_by(title: skill_title)
    if skill
      DrillSkill.find_or_create_by!(drill: drill, skill: skill)
    end
  end
end

puts "Seeded #{Drill.count} drills with skill associations"
