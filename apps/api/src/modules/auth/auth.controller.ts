import { Controller, Post, Body, Param, UseGuards } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';
import { UserRole } from '@prisma/client';
import { AuthService } from './auth.service';
import { LoginThrottleGuard } from '../../common/guards/login-throttle.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { Roles } from '../../common/decorators/roles.decorator';
import { RolesGuard } from '../../common/guards/roles.guard';

class LoginDto {
  @ApiProperty({ example: 'STAFF001' })
  @IsString()
  @MinLength(1)
  @MaxLength(20)
  employeeCode: string;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  password: string;
}

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private auth: AuthService) {}

  @Post('login')
  @UseGuards(LoginThrottleGuard)
  @ApiOperation({ summary: 'เข้าสู่ระบบ' })
  login(@Body() dto: LoginDto) {
    return this.auth.login(dto.employeeCode, dto.password);
  }

  @Post('logout-all')
  @UseGuards(AuthGuard('jwt'))
  @ApiBearerAuth()
  @ApiOperation({ summary: 'ออกจากระบบทุกอุปกรณ์ (เพิกถอน token ทั้งหมดของตัวเอง)' })
  logoutAll(@CurrentUser() user: { id: string }) {
    return this.auth.revokeSessions(user.id, user.id);
  }

  @Post('users/:id/revoke-sessions')
  @UseGuards(AuthGuard('jwt'), RolesGuard)
  @Roles(UserRole.ADMIN)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'ADMIN: เพิกถอน session ของผู้ใช้ (ลาออก/บัญชีถูกยึด)' })
  revokeUserSessions(
    @Param('id') id: string,
    @CurrentUser() actor: { id: string },
  ) {
    return this.auth.revokeSessions(id, actor.id);
  }
}
