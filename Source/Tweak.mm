#include "Macros.h"

void *(*Component_GetTransform)(void *component) = (void *(*)(void *))getRealOffset(0x100C55BA4);
void (*Transform_INTERNAL_CALL_GetPosition)(void *transform, Vector3 *out) = (void (*)(void *, Vector3 *))getRealOffset(0x100CB3DC0);

struct Vector2 {
	float x;
	float y;
};

struct me_t {
	void *object;
	Vector3 location;
	bool firing;
	int team;
};

me_t *me;

float NormalizeAngle (float angle){
	while (angle>360)
		angle -= 360;
	while (angle<0)
		angle += 360;
	return angle;
}

Vector3 NormalizeAngles (Vector3 angles){
	angles.x = NormalizeAngle (angles.x);
	angles.y = NormalizeAngle (angles.y);
	angles.z = NormalizeAngle (angles.z);
	return angles;
}

Vector3 ToEulerRad(Quaternion q1){
	float Rad2Deg = 360.0f / (M_PI * 2.0f);

	float sqw = q1.w * q1.w;
	float sqx = q1.x * q1.x;
	float sqy = q1.y * q1.y;
	float sqz = q1.z * q1.z;
	float unit = sqx + sqy + sqz + sqw;
	float test = q1.x * q1.w - q1.y * q1.z;
	Vector3 v;

	if (test>0.4995f*unit) {
		v.y = 2.0f * atan2f (q1.y, q1.x);
		v.x = M_PI / 2.0f;
		v.z = 0;
		return NormalizeAngles(v * Rad2Deg);
	}
	if (test<-0.4995f*unit) {
		v.y = -2.0f * atan2f (q1.y, q1.x);
		v.x = -M_PI / 2.0f;
		v.z = 0;
		return NormalizeAngles (v * Rad2Deg);
	}
	Quaternion q(q1.w, q1.z, q1.x, q1.y);
	v.y = atan2f (2.0f * q.x * q.w + 2.0f * q.y * q.z, 1 - 2.0f * (q.z * q.z + q.w * q.w)); // yaw
	v.x = asinf (2.0f * (q.x * q.z - q.w * q.y)); // pitch
	v.z = atan2f (2.0f * q.x * q.y + 2.0f * q.z * q.w, 1 - 2.0f * (q.y * q.y + q.z * q.z)); // roll
	return NormalizeAngles (v * Rad2Deg);
}

// utility function to grab player ids
// return: -1 if player is NULL
int GetCharacterID(void *character){
	if(!character)
		return -1;
	
	return *(int *)((uint64_t)character + 0x3c);
}

// utility function to get the health of a character
int GetCharacterHealth(void *character){
	if(!character)
		return -1;
	
	return *(int *)((uint64_t)character + 0xf4);
}

// utility function to get the location of a character
Vector3 GetCharacterLocation(void *character){
	Vector3 location;
	Transform_INTERNAL_CALL_GetPosition(Component_GetTransform(character), &location);
	
	return location;
}

// utility function to give back a nicely formatted string representing a Vector3
NSString *Vector3Desc(Vector3 v){
	return [NSString stringWithFormat:@"[x: %.3f y: %.3f z: %.3f]", v.x, v.y, v.z];
}

// utility function to give back a nicely formatted string representing a Vector2
NSString *Vector2Desc(Vector2 v){
	return [NSString stringWithFormat:@"[x: %.3f y: %.3f]", v.x, v.y];
}

// utility function to give back CharacterData object from a character
void *GetCharacterDataFromCharacter(void *character){
	return *(void **)((uint64_t)character + 0xa8);
}

// utility function to see whether or not a character is dead
bool IsCharacterDead(void *character){
	return GetCharacterHealth(character) < 1;
}

// utility function to get the team of a character
int GetCharacterTeam(void *character){
	void *player = *(void **)((uint64_t)character + 0x98);
	void *teamBoxedVal = *(void **)((uint64_t)player + 0x70);
	
	return *(int *)((uint64_t)teamBoxedVal + 0x18);
}

// utility function to get my rotation to a location
Quaternion GetRotationToLocation(Vector3 targetLocation, float y_bias){
	return Quaternion::LookRotation((targetLocation + Vector3(0, y_bias, 0)) - me->location, Vector3(0, 1, 0));
}

// utility function to figure out if a character is in the game or not
bool GetCharacterIsInitialized(void *character){
	return *(int *)((uint64_t)character + 0x110);
}

struct enemy_t {
	void *object;
	Vector3 location;
	int health;
};

class AimbotManager {
	private:
		std::vector<enemy_t *> *enemies;
		
	public:
		AimbotManager(){
			enemies = new std::vector<enemy_t *>();
		}
		
		bool isEnemyPresent(void *enemyObject){
			for(std::vector<enemy_t *>::iterator it = enemies->begin(); it != enemies->end(); it++){
				if((*it)->object == enemyObject){
					return true;
				}
			}
			
			return false;
		}
		
		void removeEnemy(enemy_t *enemy){
			for(int i = 0; i<enemies->size(); i++){
				if((*enemies)[i] == enemy){
					enemies->erase(enemies->begin() + i);
					
					return;
				}
			}
		}
		
		void tryAddEnemy(void *enemyObject){
			if(isEnemyPresent(enemyObject)){
				return;
			}
			
			if(IsCharacterDead(enemyObject)){
				return;
			}
			
			enemy_t *newEnemy = new enemy_t();
			
			newEnemy->object = enemyObject;
			newEnemy->location = GetCharacterLocation(enemyObject);
			newEnemy->health = GetCharacterHealth(enemyObject);
			
			enemies->push_back(newEnemy);
		}
		
		// remove bad enemies and update the fields for enemyObject
		void updateEnemies(void *enemyObject){
			for(int i=0; i<enemies->size(); i++){
				enemy_t *current = (*enemies)[i];
				
				if(IsCharacterDead(current->object)){
					enemies->erase(enemies->begin() + i);
				}
				
				if(me->team == GetCharacterTeam(current->object)){
					enemies->erase(enemies->begin() + i);
				}
				
				if(!GetCharacterIsInitialized(current->object)){
					enemies->erase(enemies->begin() + i);
				}
				
				if(current->object == enemyObject){
					current->location = GetCharacterLocation(current->object);
					current->health = GetCharacterHealth(current->object);
				}
			}
		}
		
		void removeEnemyGivenObject(void *enemyObject){
			for(int i = 0; i<enemies->size(); i++){
				if((*enemies)[i]->object == enemyObject){
					enemies->erase(enemies->begin() + i);
					
					return;
				}
			}
		}
		
		enemy_t *getClosestEnemy(Vector3 myLocation){
			if(enemies->empty()){
				return NULL;
			}
			
			// update before we search for a target
			updateEnemies((*enemies)[0]);
			
			float shortestDistance = 99999999.0f;
			enemy_t *closestEnemy = NULL;
			
			for(int i = 0; i<enemies->size(); i++){
				Vector3 currentLocation = (*enemies)[i]->location;
				float distanceToMe = Vector3::distance(currentLocation, myLocation);
				
				if(distanceToMe < shortestDistance){
					shortestDistance = distanceToMe;
					closestEnemy = (*enemies)[i];
				}
			}
			
			return closestEnemy;
		}
};

AimbotManager *aimbotManager;

void (*Character_Gameplay_Update)(void *character, float dt);

void _Character_Gameplay_Update(void *character, float dt){
	Character_Gameplay_Update(character, dt);
	
	if(me->object != character){
		if(me->team != GetCharacterTeam(character) && GetCharacterIsInitialized(character)){
			aimbotManager->tryAddEnemy(character);
		}
	
		aimbotManager->updateEnemies(character);
	}
}

void (*Character_SetRotation)(void *character, Vector2 rotation);

void _Character_SetRotation(void *character, Vector2 rotation){
	if(__builtin_return_address(0) == (void *)getRealOffset(0x1002A1088)){
		me->object = character;
		me->team = GetCharacterTeam(me->object);
		me->location = GetCharacterLocation(me->object);
		
		void *characterData = GetCharacterDataFromCharacter(character);
	
		if(characterData){
			me->firing = *(char *)((uint64_t)characterData + 0x36);
		}
		
		enemy_t *target = aimbotManager->getClosestEnemy(me->location);
		
		if(target){
			// this game doesn't use a Quaternion for our rotation
			// it uses a two dimensional vector, which is odd but whatever
			// to compensate, we can make our hacked rotation and then get euler angles from that
			Vector3 angles = ToEulerRad(GetRotationToLocation(target->location, -0.65f));
			
			rotation.x = angles.x;
			rotation.y = angles.y;
			
			// max rotation seems to be [275, 80], and we don't want to go out of bounds!
			// no check needed for y value since the game actually has a limit to how high we can look up
			if(rotation.x >= 275.0f)
				rotation.x -= 360.0f;
			if(rotation.x <= -275.0f)
				rotation.x += 360.0f;
			
		}
	}
	
	Character_SetRotation(character, rotation);
}

void (*Character_Destroy)(void *character);

void _Character_Destroy(void *character){
	Character_Destroy(character);
	
	// don't aim at people who have left the game
	aimbotManager->removeEnemyGivenObject(character);
}

%ctor {
	aimbotManager = new AimbotManager();
	me = new me_t();
	
	HOOK(0x1002625B4, _Character_Gameplay_Update, Character_Gameplay_Update);
	HOOK(0x100260E04, _Character_SetRotation, Character_SetRotation);
	HOOK(0x100261F28, _Character_Destroy, Character_Destroy);
}

uint64_t getRealOffset(uint64_t offset){
    return _dyld_get_image_vmaddr_slide(0) + offset;
}
