import { AbilityStage, Configuration } from '@kit.AbilityKit';

export default class AppAbilityStage extends AbilityStage {
  onCreate(): void {
    console.info('[hm-agent] AppAbilityStage onCreate');
  }

  onConfigurationUpdate(newConfig: Configuration): void {
  }
}
