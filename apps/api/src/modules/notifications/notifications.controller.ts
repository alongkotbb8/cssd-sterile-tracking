import { Body, Controller, Delete, Post, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { NotificationsService } from './notifications.service';
import { RegisterTokenDto } from './dto/register-token.dto';

@ApiTags('notifications')
@ApiBearerAuth()
@UseGuards(AuthGuard('jwt'))
@Controller('notifications')
export class NotificationsController {
  constructor(private svc: NotificationsService) {}

  @Post('fcm-token')
  register(@Body() dto: RegisterTokenDto, @CurrentUser() user: { id: string }) {
    return this.svc.registerToken(user.id, dto.token, dto.deviceId);
  }

  @Delete('fcm-token')
  unregister(@Body() dto: RegisterTokenDto) {
    return this.svc.unregisterToken(dto.token);
  }
}
